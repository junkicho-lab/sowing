# frozen_string_literal: true

require "rack/test"

# Phase 13 W28-T01 — 17번째 합성기 self-mirror 라우트·UI 통합.
RSpec.describe "자기 거울 (5축) UI (Phase 13 W28-T01)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:original_key) { ENV["ANTHROPIC_API_KEY"] }

  before do
    header "Host", "127.0.0.1"
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    %w[00_Inbox 20_Notes 30_Records .sowing/synth].each { |d| FileUtils.rm_rf(vault_dir.join(d)) }
  end

  after { ENV["ANTHROPIC_API_KEY"] = original_key }

  describe "SYNTH_TYPES — 17번째 등록" do
    it "self-mirror type 정의 + subdir/label/icon/accept_category" do
      meta = Sowing::Controllers::SynthController::SYNTH_TYPES["self-mirror"]
      expect(meta).not_to be_nil
      expect(meta[:subdir]).to eq("self-mirror")
      expect(meta[:label]).to include("자기 거울")
      expect(meta[:icon]).to eq("🌅")
      expect(meta[:accept_category]).to eq("회고")
    end

    it "전체 17 type" do
      expect(Sowing::Controllers::SynthController::SYNTH_TYPES.size).to eq(17)
    end
  end

  describe "GET /synth — 폼 노출" do
    it "self-mirror 섹션 + 폼 표시" do
      get "/synth"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("자기 거울 (5축)")
      expect(last_response.body).to include("🌅")
      expect(last_response.body).to include("📅 오늘 (1일)")
      expect(last_response.body).to include("📋 이번 주 (7일)")
    end

    it "5축 안내 hint" do
      get "/synth"
      expect(last_response.body).to include("지성·감정·습관·관계·에너지")
    end
  end

  describe "POST /synth/self-mirror/auto/generate" do
    def seed(n: 5, at_base: Time.new(2026, 5, 11, 9, 0, 0))
      n.times do |i|
        Timecop.freeze(at_base + i * 3600) do
          Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
            .call(body: "협동학습 잘됐 보람 #{i}")
        end
      end
    end

    it "default daily + 오늘 기준 자동" do
      seed
      Timecop.freeze(Time.new(2026, 5, 11, 18, 0, 0)) do
        post "/synth/self-mirror/auto/generate", period: "daily"
      end
      expect(last_response.status).to eq(302)
      # redirect 가 /synth/self-mirror/{slug} 로
      expect(last_response.location).to match(%r{/synth/self-mirror/daily-2026-05-11})
    end

    it "weekly 명시" do
      Date.new(2026, 5, 4).upto(Date.new(2026, 5, 10)) do |d|
        Timecop.freeze(Time.new(d.year, d.month, d.day, 10, 0, 0)) do
          Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
            .call(body: "x")
        end
      end

      post "/synth/self-mirror/auto/generate", period: "weekly", date: "2026-W19"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include("weekly-2026-W19")
    end

    it "entries 부족 → 실패 redirect /synth + flash 안내" do
      Timecop.freeze(Time.new(2026, 5, 11, 9, 0, 0)) do
        Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
          .call(body: "혼자")
      end

      Timecop.freeze(Time.new(2026, 5, 11, 18, 0, 0)) do
        post "/synth/self-mirror/auto/generate", period: "daily"
      end
      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/synth")
    end

    it "잘못된 period → daily 폴백 (allowlist)" do
      seed
      Timecop.freeze(Time.new(2026, 5, 11, 18, 0, 0)) do
        post "/synth/self-mirror/auto/generate", period: "yearly"
      end
      expect(last_response.status).to eq(302)
      # 자동 daily 로 fallback 됐다면 daily-2026-05-11 로 redirect
      expect(last_response.location).to match(%r{daily-})
    end
  end

  describe "LLM toggle — self-mirror 도 5번째 LLM-capable" do
    it "키 있음 + llm=1 → Anthropic backend 주입 (use case 호출 검증은 use case spec 으로)" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
      Timecop.freeze(Time.new(2026, 5, 11, 9, 0, 0)) do
        5.times { |i|
          Timecop.freeze(Time.new(2026, 5, 11, 9 + i, 0, 0)) do
            Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
              .call(body: "x #{i}")
          end
        }
      end

      injected = nil
      allow(Sowing::UseCases::SynthesizeSelfMirror).to receive(:new) do |kwargs|
        injected = kwargs[:llm_backend]
        instance_double(Sowing::UseCases::SynthesizeSelfMirror,
          call: Dry::Monads::Result::Failure.new(:no_entries))
      end

      post "/synth/self-mirror/auto/generate",
        period: "daily", date: "2026-05-11", llm: "1"

      expect(injected).to be_a(Sowing::Eval::Backends::Anthropic)
    end
  end
end
