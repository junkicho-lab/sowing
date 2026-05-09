# frozen_string_literal: true

require "front_matter_parser"
require "yaml"

# eval 코퍼스 contract test (W13-T01).
# 100건 모두 frontmatter + body + 평가 메타데이터 포함을 강제.
RSpec.describe "eval/corpus/teacher_writings (W13-T01)" do
  let(:corpus_root) { File.expand_path("../../eval/corpus/teacher_writings", __dir__) }
  let(:hand_crafted_dir) { File.join(corpus_root, "hand_crafted") }
  let(:generated_dir) { File.join(corpus_root, "generated") }

  let(:all_files) {
    Dir.glob(File.join(corpus_root, "**/*.md")).sort
  }

  let(:cases) {
    all_files.map do |path|
      parsed = FrontMatterParser::Parser.new(:md).call(File.read(path))
      {path: path, fm: parsed.front_matter, body: parsed.content}
    end
  }

  describe "코퍼스 크기 (ROADMAP W13-T01)" do
    it "정확히 100건 (hand_crafted + generated)" do
      expect(all_files.size).to eq(100)
    end

    it "hand_crafted ≥ 10건 (시드)" do
      expect(Dir.glob(File.join(hand_crafted_dir, "*.md")).size).to be >= 10
    end

    it "generated ≥ 80건 (자동 변형)" do
      expect(Dir.glob(File.join(generated_dir, "*.md")).size).to be >= 80
    end
  end

  describe "frontmatter 필수 키 (모든 케이스)" do
    it "case_id / task / hand_crafted / eval_dimensions / expected_output 모두 존재" do
      cases.each do |c|
        %w[case_id task hand_crafted eval_dimensions expected_output].each do |key|
          expect(c[:fm]).to have_key(key), "#{File.basename(c[:path])}: '#{key}' 누락"
        end
      end
    end

    it "case_id 는 모두 고유" do
      ids = cases.map { |c| c[:fm]["case_id"] }
      expect(ids.uniq.size).to eq(ids.size)
    end

    it "case_id 형식 — {prefix}-{NNN} 또는 {prefix}-gen-{NNN}" do
      cases.each do |c|
        id = c[:fm]["case_id"]
        expect(id).to match(/\A[a-z]{3}(-gen)?-\d{3}\z/), "#{File.basename(c[:path])}: case_id '#{id}' 형식 오류"
      end
    end
  end

  describe "task type (6종 모두 사용)" do
    it "task 는 schema 의 6종 중 하나" do
      allowed = %w[entity_extraction student_digest gap_detection reflection contradiction general]
      cases.each do |c|
        expect(allowed).to include(c[:fm]["task"]), "#{File.basename(c[:path])}: 알 수 없는 task '#{c[:fm]["task"]}'"
      end
    end

    it "6 task type 모두 ≥ 1건 사용" do
      tasks = cases.map { |c| c[:fm]["task"] }.uniq
      expect(tasks).to contain_exactly(
        "entity_extraction", "student_digest", "gap_detection",
        "reflection", "contradiction", "general"
      )
    end
  end

  describe "eval_dimensions" do
    it "모든 케이스 ≥ 1개 차원" do
      cases.each do |c|
        dims = c[:fm]["eval_dimensions"]
        expect(dims).to be_a(Array)
        expect(dims).not_to be_empty, "#{File.basename(c[:path])}: eval_dimensions 비어 있음"
      end
    end

    it "차원 이름은 schema 정의 안에서만" do
      allowed = %w[
        factuality coverage conciseness relevance format
        korean_consistency tone precision recall evidence
        insight structure
      ]
      cases.each do |c|
        c[:fm]["eval_dimensions"].each do |d|
          expect(allowed).to include(d), "#{File.basename(c[:path])}: 알 수 없는 차원 '#{d}'"
        end
      end
    end
  end

  describe "본문 + expected_output" do
    it "본문 비어 있지 않음 (10자 이상)" do
      cases.each do |c|
        expect(c[:body].strip.length).to be >= 10, "#{File.basename(c[:path])}: body 너무 짧음"
      end
    end

    it "expected_output 비어 있지 않음" do
      cases.each do |c|
        eo = c[:fm]["expected_output"]
        expect(eo).not_to be_nil
        # Hash, String, Array 모두 허용 (task 별로 형식 다름)
        if eo.is_a?(String)
          expect(eo.strip).not_to be_empty
        end
      end
    end
  end

  describe "hand_crafted 플래그" do
    it "hand_crafted/ 의 모든 파일은 hand_crafted: true" do
      Dir.glob(File.join(hand_crafted_dir, "*.md")).each do |path|
        fm = FrontMatterParser::Parser.new(:md).call(File.read(path)).front_matter
        expect(fm["hand_crafted"]).to be(true), "#{File.basename(path)}: hand_crafted 플래그 오류"
      end
    end

    it "generated/ 의 모든 파일은 hand_crafted: false" do
      Dir.glob(File.join(generated_dir, "*.md")).each do |path|
        fm = FrontMatterParser::Parser.new(:md).call(File.read(path)).front_matter
        expect(fm["hand_crafted"]).to be(false), "#{File.basename(path)}: hand_crafted 플래그 오류"
      end
    end
  end

  describe "SCHEMA.md 존재" do
    it "코퍼스 root 에 SCHEMA.md 있음" do
      expect(File).to exist(File.expand_path("../../eval/corpus/SCHEMA.md", __dir__))
    end
  end
end
