# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Sowing::Eval::Runner do
  let(:tmpdir) { Pathname.new(Dir.mktmpdir("eval-runner-spec-")) }
  let(:corpus_dir) { tmpdir.join("corpus") }

  after { FileUtils.rm_rf(tmpdir) if tmpdir.exist? }

  def create_case(case_id, task, dims, expected = "ok")
    FileUtils.mkdir_p(corpus_dir)
    fm = {
      "case_id" => case_id,
      "task" => task,
      "hand_crafted" => true,
      "eval_dimensions" => dims,
      "expected_output" => expected
    }
    File.write(corpus_dir.join("#{case_id}.md"),
      "---\n#{YAML.dump(fm).delete_prefix("---\n")}---\n# #{case_id}\nbody for #{case_id}\n")
  end

  describe "#run (self-eval baseline)" do
    before do
      create_case("ent-001", "entity_extraction", %w[factuality coverage])
      create_case("ref-001", "reflection", %w[structure conciseness])
    end

    it "전체 corpus 순회 → 모든 case 평가 결과 포함" do
      runner = described_class.new
      payload = runner.run(corpus_dir: corpus_dir.to_s)

      expect(payload["corpus_size"]).to eq(2)
      expect(payload["cases"].size).to eq(2)
      expect(payload["cases"].map { |c| c["case_id"] }).to contain_exactly("ent-001", "ref-001")
      expect(payload["run_id"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(payload["backend"]).to eq("FakeBackend")
      expect(payload["model"]).to eq("fake-baseline")
    end

    it "summary 에 차원별 avg/min/max/n 포함" do
      runner = described_class.new
      payload = runner.run(corpus_dir: corpus_dir.to_s)
      summary = payload["summary"]
      # FakeBackend baseline 은 모든 차원 score=3
      %w[factuality coverage structure conciseness].each do |dim|
        expect(summary[dim]["avg"]).to eq(3.0)
        expect(summary[dim]["min"]).to eq(3)
        expect(summary[dim]["max"]).to eq(3)
      end
    end

    it "only_task 필터" do
      runner = described_class.new
      payload = runner.run(corpus_dir: corpus_dir.to_s, only_task: "reflection")
      expect(payload["corpus_size"]).to eq(1)
      expect(payload["cases"].first["case_id"]).to eq("ref-001")
    end

    it "limit 적용" do
      runner = described_class.new
      payload = runner.run(corpus_dir: corpus_dir.to_s, limit: 1)
      expect(payload["corpus_size"]).to eq(1)
    end

    it "corpus_dir 없으면 빈 결과 (graceful)" do
      runner = described_class.new
      payload = runner.run(corpus_dir: "/nonexistent")
      expect(payload["corpus_size"]).to eq(0)
      expect(payload["cases"]).to eq([])
    end
  end

  describe "synthesizer 주입 (Phase 11+ 합성기 미리보기)" do
    before { create_case("ent-001", "entity_extraction", %w[factuality]) }

    it "synthesizer Proc 호출되어 LLM 출력 만들고 judge 평가" do
      synth_called = []
      synthesizer = ->(case_data) {
        synth_called << case_data[:fm]["case_id"]
        "synthesized output"
      }

      runner = described_class.new(synthesizer: synthesizer)
      payload = runner.run(corpus_dir: corpus_dir.to_s)

      expect(synth_called).to eq(["ent-001"])
      expect(payload["cases"].first["scores"]["factuality"]["score"]).to eq(3) # FakeBackend baseline
    end
  end

  describe "실제 corpus (eval/corpus/teacher_writings/) 으로" do
    it "100건 모두 평가 가능 (회귀 baseline)" do
      runner = described_class.new
      payload = runner.run(corpus_dir: File.expand_path("../../eval/corpus/teacher_writings", __dir__))
      expect(payload["corpus_size"]).to eq(100)
      expect(payload["cases"].size).to eq(100)
      # FakeBackend baseline 이라 모든 차원 평균 3.0 일 것
      payload["summary"].each_value do |stats|
        expect(stats["avg"]).to eq(3.0)
      end
    end
  end
end

RSpec.describe Sowing::Eval::ResultStore do
  let(:tmpdir) { Pathname.new(Dir.mktmpdir("result-store-spec-")) }
  let(:store) { described_class.new(root: tmpdir) }

  after { FileUtils.rm_rf(tmpdir) if tmpdir.exist? }

  describe "#save / #all" do
    it "JSON 파일로 저장 + all 로 조회" do
      payload = {"run_id" => "2026-05-10T10:00:00", "summary" => {}}
      path = store.save(payload)
      expect(path).to exist
      expect(store.all.first["run_id"]).to eq("2026-05-10T10:00:00")
    end

    it "여러 run 시간순 정렬" do
      store.save({"run_id" => "2026-05-10T10:00:00"})
      store.save({"run_id" => "2026-05-10T11:00:00"})
      store.save({"run_id" => "2026-05-10T09:00:00"})

      ids = store.all.map { |r| r["run_id"] }
      expect(ids).to eq(%w[2026-05-10T09-00-00 2026-05-10T10-00-00 2026-05-10T11-00-00])
        .or eq(%w[2026-05-10T09:00:00 2026-05-10T10:00:00 2026-05-10T11:00:00])
    end

    it "콜론 포함 run_id 도 안전 (파일명 sanitize)" do
      payload = {"run_id" => "2026-05-10T10:30:45"}
      path = store.save(payload)
      expect(path.to_s).not_to include(":")
      expect(path).to exist
    end
  end

  describe "#compare_to_previous (회귀 감지)" do
    it "직전 결과 없으면 regressed=false + 사유" do
      diff = store.compare_to_previous
      expect(diff[:regressed]).to be false
    end

    it "차원 평균 동일 → regressed=false" do
      store.save({"run_id" => "1", "summary" => {"factuality" => {"avg" => 3.0}}})
      store.save({"run_id" => "2", "summary" => {"factuality" => {"avg" => 3.0}}})
      diff = store.compare_to_previous
      expect(diff[:regressed]).to be false
      expect(diff[:dimensions]["factuality"][:delta]).to eq(0.0)
    end

    it "0.5 이상 하락 → regressed=true" do
      store.save({"run_id" => "1", "summary" => {"factuality" => {"avg" => 4.0}}})
      store.save({"run_id" => "2", "summary" => {"factuality" => {"avg" => 3.0}}})
      diff = store.compare_to_previous
      expect(diff[:regressed]).to be true
      expect(diff[:dimensions]["factuality"][:delta]).to eq(-1.0)
    end

    it "0.5 미만 하락 → regressed=false" do
      store.save({"run_id" => "1", "summary" => {"factuality" => {"avg" => 4.0}}})
      store.save({"run_id" => "2", "summary" => {"factuality" => {"avg" => 3.7}}})
      diff = store.compare_to_previous
      expect(diff[:regressed]).to be false
    end

    it "threshold 인자로 임계값 조정" do
      store.save({"run_id" => "1", "summary" => {"factuality" => {"avg" => 4.0}}})
      store.save({"run_id" => "2", "summary" => {"factuality" => {"avg" => 3.7}}})
      diff = store.compare_to_previous(threshold: 0.2)
      expect(diff[:regressed]).to be true
    end

    it "ROADMAP 검증 — 의도적 회귀 시뮬레이션" do
      # baseline: 평균 3.0
      store.save({"run_id" => "baseline", "summary" => {"factuality" => {"avg" => 3.0}, "coverage" => {"avg" => 3.0}}})
      # corrupted: factuality 1.0 으로 떨어짐
      store.save({"run_id" => "corrupted", "summary" => {"factuality" => {"avg" => 1.0}, "coverage" => {"avg" => 3.0}}})

      diff = store.compare_to_previous
      expect(diff[:regressed]).to be true
      expect(diff[:dimensions]["factuality"][:delta]).to eq(-2.0)
      expect(diff[:dimensions]["coverage"][:delta]).to eq(0.0)
    end
  end
end
