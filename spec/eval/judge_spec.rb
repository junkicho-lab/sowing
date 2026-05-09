# frozen_string_literal: true

require "json"

RSpec.describe Sowing::Eval::Judge do
  let(:case_data) {
    {
      fm: {
        "case_id" => "ent-001",
        "task" => "entity_extraction",
        "eval_dimensions" => %w[factuality coverage format],
        "expected_output" => {"students" => ["민준"], "subjects" => ["수학"]}
      },
      body: "민준이가 수학 시간에 발표 자원."
    }
  }

  let(:llm_output) { '{"students": ["민준"], "subjects": ["수학"]}' }

  describe "#evaluate (FakeBackend default)" do
    subject(:judge) { described_class.new }

    it "FakeBackend baseline 응답 → 모든 차원 score=3" do
      result = judge.evaluate(case_data: case_data, llm_output: llm_output)
      expect(result.keys).to contain_exactly("factuality", "coverage", "format")
      result.each_value do |entry|
        expect(entry["score"]).to eq(3)
        expect(entry["reason"]).to include("baseline")
      end
    end

    it "case_data 의 eval_dimensions 만 평가 — 다른 차원 없음" do
      result = judge.evaluate(case_data: case_data, llm_output: llm_output)
      expect(result.keys).not_to include("relevance")
      expect(result.keys).not_to include("tone")
    end

    it "system + user prompt 를 backend 에 전달" do
      judge.evaluate(case_data: case_data, llm_output: llm_output)
      captured = judge.backend.captured_prompts.first
      expect(captured[:system]).to include("Korean", "0~5", "JSON")
      expect(captured[:user]).to include("ent-001").or include("entity_extraction")
      expect(captured[:user]).to include("민준") # 입력 본문 포함
      expect(captured[:user]).to include(llm_output)
    end
  end

  describe "응답 파싱" do
    it "올바른 JSON → 그대로 파싱" do
      response = JSON.generate({
        "factuality" => {"score" => 5, "reason" => "정확"},
        "coverage" => {"score" => 4, "reason" => "잘 다룸"},
        "format" => {"score" => 5, "reason" => "스키마 일치"}
      })
      backend = Sowing::Eval::Backends::FakeBackend.new(responses: [response])
      judge = described_class.new(backend: backend)

      result = judge.evaluate(case_data: case_data, llm_output: llm_output)
      expect(result["factuality"]["score"]).to eq(5)
      expect(result["factuality"]["reason"]).to eq("정확")
      expect(result["coverage"]["score"]).to eq(4)
    end

    it "JSON 파싱 실패 → 모든 차원 score=0 + 사유 명시" do
      backend = Sowing::Eval::Backends::FakeBackend.new(responses: ["not a json"])
      judge = described_class.new(backend: backend)
      result = judge.evaluate(case_data: case_data, llm_output: llm_output)
      result.each_value do |entry|
        expect(entry["score"]).to eq(0)
        expect(entry["reason"]).to include("JSON 파싱 실패")
      end
    end

    it "차원 누락 → score=0 + 누락 사유" do
      response = JSON.generate({"factuality" => {"score" => 5, "reason" => "OK"}})
      backend = Sowing::Eval::Backends::FakeBackend.new(responses: [response])
      judge = described_class.new(backend: backend)
      result = judge.evaluate(case_data: case_data, llm_output: llm_output)
      expect(result["factuality"]["score"]).to eq(5)
      expect(result["coverage"]["score"]).to eq(0)
      expect(result["coverage"]["reason"]).to include("누락")
    end

    it "score 가 0~5 범위 밖 → clamp" do
      response = JSON.generate({
        "factuality" => {"score" => 99, "reason" => "x"},
        "coverage" => {"score" => -3, "reason" => "y"},
        "format" => {"score" => 5, "reason" => "z"}
      })
      backend = Sowing::Eval::Backends::FakeBackend.new(responses: [response])
      judge = described_class.new(backend: backend)
      result = judge.evaluate(case_data: case_data, llm_output: llm_output)
      expect(result["factuality"]["score"]).to eq(5) # clamp 99 → 5
      expect(result["coverage"]["score"]).to eq(0)   # clamp -3 → 0
      expect(result["format"]["score"]).to eq(5)
    end
  end

  describe "ALL_DIMENSIONS — schema 와 일치" do
    it "12 차원 모두 정의 (SCHEMA.md §4)" do
      expect(described_class::ALL_DIMENSIONS).to contain_exactly(
        "factuality", "coverage", "conciseness", "relevance", "format",
        "korean_consistency", "tone", "precision", "recall", "evidence",
        "insight", "structure"
      )
    end
  end
end
