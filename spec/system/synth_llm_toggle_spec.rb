# frozen_string_literal: true

require "rack/test"

# UI 의 LLM 토글 동작 검증 — 키 유무에 따라 체크박스 또는 안내 표시,
# 폼 제출 시 backend 가 use case 에 정확히 주입/미주입 되는지.
#
# 4 type 중 contradictions 만 대표로 검증 (controller 코드 패턴 동일).
RSpec.describe "합성기 LLM 모드 toggle", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  let(:original_key) { ENV["ANTHROPIC_API_KEY"] }
  before { header "Host", "127.0.0.1" }
  after { ENV["ANTHROPIC_API_KEY"] = original_key }

  describe "GET /synth — 토글 표시 분기" do
    it "ANTHROPIC_API_KEY 미설정 → 안내 메시지 + 체크박스 없음" do
      ENV.delete("ANTHROPIC_API_KEY")
      get "/synth"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("<strong>LLM 모드 사용</strong>")
      expect(last_response.body).to include("ANTHROPIC_API_KEY")
      expect(last_response.body).not_to match(%r{<input[^>]*name=["']llm["']})
    end

    it "ANTHROPIC_API_KEY 설정됨 → 체크박스 + 모델 드롭다운 + 비용 안내" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
      get "/synth"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to match(%r{<input[^>]*name=["']llm["']})
      # 모델 드롭다운 (3 모델 카탈로그)
      expect(last_response.body).to match(%r{<select[^>]*name=["']model["']})
      expect(last_response.body).to include("Haiku 4.5")
      expect(last_response.body).to include("Sonnet 4.5")
      expect(last_response.body).to include("Opus 4.7")
      # 비용 안내 (Haiku ≈ $0.0080, Sonnet ≈ $0.0240, Opus ≈ $0.1200)
      expect(last_response.body).to include("$0.0080")
      expect(last_response.body).to include("$0.0240")
      expect(last_response.body).to include("$0.1200")
      # Haiku 가 default selected
      expect(last_response.body).to match(%r{<option[^>]*selected[^>]*>\s*Haiku 4.5})
    end
  end

  describe "POST 시 backend 주입 분기" do
    it "키 있음 + llm=1 → Anthropic backend 주입" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

      injected = nil
      allow(Sowing::UseCases::DetectContradictions).to receive(:new) do |kwargs|
        injected = kwargs[:llm_backend]
        instance_double(Sowing::UseCases::DetectContradictions,
          call: Dry::Monads::Result::Failure.new(:no_observations))
      end

      post "/synth/contradictions/observations/generate", llm: "1"

      expect(injected).to be_a(Sowing::Eval::Backends::Anthropic)
    end

    it "키 있음 + llm 미체크 → backend nil (결정적 모드)" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

      injected = :unset
      allow(Sowing::UseCases::DetectContradictions).to receive(:new) do |kwargs|
        injected = kwargs[:llm_backend]
        instance_double(Sowing::UseCases::DetectContradictions,
          call: Dry::Monads::Result::Failure.new(:no_observations))
      end

      post "/synth/contradictions/observations/generate"

      expect(injected).to be_nil
    end

    it "llm=1 이지만 키 미설정 → backend nil (안전 fallback)" do
      ENV.delete("ANTHROPIC_API_KEY")

      injected = :unset
      allow(Sowing::UseCases::DetectContradictions).to receive(:new) do |kwargs|
        injected = kwargs[:llm_backend]
        instance_double(Sowing::UseCases::DetectContradictions,
          call: Dry::Monads::Result::Failure.new(:no_observations))
      end

      post "/synth/contradictions/observations/generate", llm: "1"

      expect(injected).to be_nil
    end

    it "ANTHROPIC_MODEL ENV 설정 → 해당 모델로 backend 생성" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
      ENV["ANTHROPIC_MODEL"] = "claude-sonnet-4-5-20250929"

      injected = nil
      allow(Sowing::UseCases::DetectContradictions).to receive(:new) do |kwargs|
        injected = kwargs[:llm_backend]
        instance_double(Sowing::UseCases::DetectContradictions,
          call: Dry::Monads::Result::Failure.new(:no_observations))
      end

      post "/synth/contradictions/observations/generate", llm: "1"

      expect(injected.model).to eq("claude-sonnet-4-5-20250929")
    ensure
      ENV.delete("ANTHROPIC_MODEL")
    end

    it "폼 model 파라미터 > ENV ANTHROPIC_MODEL > DEFAULT_MODEL 우선순위" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
      ENV["ANTHROPIC_MODEL"] = "claude-sonnet-4-5-20250929"

      injected = nil
      allow(Sowing::UseCases::DetectContradictions).to receive(:new) do |kwargs|
        injected = kwargs[:llm_backend]
        instance_double(Sowing::UseCases::DetectContradictions,
          call: Dry::Monads::Result::Failure.new(:no_observations))
      end

      # 폼이 Opus 명시 → ENV Sonnet 무시
      post "/synth/contradictions/observations/generate", llm: "1", model: "claude-opus-4-7"

      expect(injected.model).to eq("claude-opus-4-7")
    ensure
      ENV.delete("ANTHROPIC_MODEL")
    end

    it "카탈로그에 없는 model 문자열 → DEFAULT_MODEL 폴백 (allowlist 보안)" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

      injected = nil
      allow(Sowing::UseCases::DetectContradictions).to receive(:new) do |kwargs|
        injected = kwargs[:llm_backend]
        instance_double(Sowing::UseCases::DetectContradictions,
          call: Dry::Monads::Result::Failure.new(:no_observations))
      end

      post "/synth/contradictions/observations/generate",
        llm: "1", model: "gpt-4-evil-injection"

      expect(injected.model).to eq(Sowing::Eval::Backends::Anthropic::DEFAULT_MODEL)
    end
  end

  describe "Anthropic.estimated_cost_per_synth" do
    it "각 모델마다 양수 비용 반환 + Haiku < Sonnet < Opus 순" do
      haiku = Sowing::Eval::Backends::Anthropic.estimated_cost_per_synth("claude-haiku-4-5-20251001")
      sonnet = Sowing::Eval::Backends::Anthropic.estimated_cost_per_synth("claude-sonnet-4-5-20250929")
      opus = Sowing::Eval::Backends::Anthropic.estimated_cost_per_synth("claude-opus-4-7")

      expect(haiku).to be > 0
      expect(sonnet).to be > haiku
      expect(opus).to be > sonnet
    end

    it "알 수 없는 모델 → nil" do
      expect(Sowing::Eval::Backends::Anthropic.estimated_cost_per_synth("unknown")).to be_nil
    end
  end
end
