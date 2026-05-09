# frozen_string_literal: true

require "json"

RSpec.describe Sowing::Eval::Backends::Base do
  it "#chat 기본 구현은 NotImplementedError" do
    expect { described_class.new.chat(system: "x", user: "y") }
      .to raise_error(NotImplementedError, /chat 미구현/)
  end

  it "#name 은 클래스 이름의 마지막 segment" do
    expect(described_class.new.name).to eq("Base")
  end
end

RSpec.describe Sowing::Eval::Backends::FakeBackend do
  describe "#chat" do
    it "responses 미지정 → baseline_json (모든 차원 score=3)" do
      backend = described_class.new
      raw = backend.chat(system: "x", user: "y")
      parsed = JSON.parse(raw)
      Sowing::Eval::Judge::ALL_DIMENSIONS.each do |dim|
        expect(parsed[dim]["score"]).to eq(3)
        expect(parsed[dim]["reason"]).to include("baseline")
      end
    end

    it "responses 지정 시 호출 순서대로 반환" do
      backend = described_class.new(responses: ["first", "second"])
      expect(backend.chat(system: "x", user: "y")).to eq("first")
      expect(backend.chat(system: "x", user: "y")).to eq("second")
    end

    it "responses 소진 후에는 default 반환" do
      backend = described_class.new(responses: ["only"])
      backend.chat(system: "x", user: "y")
      next_response = backend.chat(system: "x", user: "y")
      expect(next_response).to eq(described_class.baseline_json)
    end

    it "captured_prompts 로 호출 내역 검증 가능" do
      backend = described_class.new
      backend.chat(system: "sys1", user: "user1")
      backend.chat(system: "sys2", user: "user2")
      expect(backend.captured_prompts).to eq([
        {system: "sys1", user: "user1"},
        {system: "sys2", user: "user2"}
      ])
      expect(backend.call_count).to eq(2)
    end
  end
end

RSpec.describe Sowing::Eval::Backends::OpenAI do
  describe "#initialize" do
    it "기본 모델 gpt-4o-mini" do
      backend = described_class.new(api_key: "fake")
      expect(backend.model).to eq("gpt-4o-mini")
    end

    it "환경 변수 OPENAI_API_KEY 자동 로드" do
      ENV["OPENAI_API_KEY"] = "env-key"
      backend = described_class.new
      expect(backend.instance_variable_get(:@api_key)).to eq("env-key")
    ensure
      ENV.delete("OPENAI_API_KEY")
    end
  end

  describe "#build_payload" do
    let(:backend) { described_class.new(api_key: "fake", model: "gpt-4o") }

    it "Chat Completions 표준 구조" do
      payload = backend.build_payload("system msg", "user msg")
      expect(payload[:model]).to eq("gpt-4o")
      expect(payload[:messages]).to eq([
        {role: "system", content: "system msg"},
        {role: "user", content: "user msg"}
      ])
      expect(payload[:response_format][:type]).to eq("json_object")
      expect(payload[:temperature]).to eq(0)
    end
  end

  describe "#chat (실제 호출)" do
    it "API 키 없으면 RuntimeError" do
      ENV.delete("OPENAI_API_KEY")
      backend = described_class.new(api_key: nil)
      expect { backend.chat(system: "x", user: "y") }
        .to raise_error(RuntimeError, /OPENAI_API_KEY/)
    end
  end
end

RSpec.describe Sowing::Eval::Backends::Anthropic do
  describe "#build_payload" do
    let(:backend) { described_class.new(api_key: "fake", model: "claude-haiku-4") }

    it "Messages API 구조 — system 별도 필드" do
      payload = backend.build_payload("system msg", "user msg")
      expect(payload[:model]).to eq("claude-haiku-4")
      expect(payload[:system]).to eq("system msg")
      expect(payload[:messages]).to eq([{role: "user", content: "user msg"}])
      expect(payload[:max_tokens]).to be > 0
    end
  end

  describe "#chat (실제 호출)" do
    it "API 키 없으면 RuntimeError" do
      ENV.delete("ANTHROPIC_API_KEY")
      backend = described_class.new(api_key: nil)
      expect { backend.chat(system: "x", user: "y") }
        .to raise_error(RuntimeError, /ANTHROPIC_API_KEY/)
    end
  end
end

RSpec.describe Sowing::Eval::Backends::Ollama do
  describe "#build_payload" do
    let(:backend) { described_class.new(model: "llama3.2") }

    it "format=json + temperature=0 (결정적)" do
      payload = backend.build_payload("system msg", "user msg")
      expect(payload[:model]).to eq("llama3.2")
      expect(payload[:format]).to eq("json")
      expect(payload[:options][:temperature]).to eq(0)
      expect(payload[:stream]).to be(false)
    end

    it "system + user role 둘 다 messages 에" do
      payload = described_class.new.build_payload("S", "U")
      expect(payload[:messages]).to eq([
        {role: "system", content: "S"},
        {role: "user", content: "U"}
      ])
    end
  end
end

RSpec.describe "Judge + Backend 통합" do
  it "FakeBackend → Judge 정상 동작 (단위 회귀)" do
    backend = Sowing::Eval::Backends::FakeBackend.new
    judge = Sowing::Eval::Judge.new(backend: backend)
    result = judge.evaluate(
      case_data: {fm: {"eval_dimensions" => %w[factuality]}, body: "x"},
      llm_output: "y"
    )
    expect(result["factuality"]["score"]).to eq(3)
  end

  it "Judge 는 임의 Backend (Base 인터페이스만 구현) 수용" do
    custom = Class.new(Sowing::Eval::Backends::Base) do
      def chat(system:, user:)
        '{"factuality": {"score": 5, "reason": "전부 정답"}}'
      end
    end
    judge = Sowing::Eval::Judge.new(backend: custom.new)
    result = judge.evaluate(
      case_data: {fm: {"eval_dimensions" => %w[factuality]}, body: "x"},
      llm_output: "y"
    )
    expect(result["factuality"]["score"]).to eq(5)
  end
end
