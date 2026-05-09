# frozen_string_literal: true

require "front_matter_parser"
require "json"
require "pathname"
require "time"

module Sowing
  module Eval
    # Eval Runner — corpus 전체 순회 + judge 호출 + 결과 집계 (W13-T03).
    #
    # Phase 11+ 합성기가 도입되기 전 단계: self-eval baseline 모드 — case 의
    # expected_output 자체를 LLM 출력으로 간주하고 judge 호출. 점수가 baseline 으로
    # 회귀 비교의 base 가 됨.
    #
    # 합성기 도입 후 (Phase 11+): synthesizer 를 주입받아 case 본문을 입력으로
    # 합성 실행 → 결과를 judge 평가.
    #
    # 사용:
    #   runner = Runner.new(backend: Backends::FakeBackend.new)
    #   payload = runner.run(corpus_dir: "eval/corpus/teacher_writings")
    #   ResultStore.new.save(payload)
    class Runner
      DEFAULT_CORPUS_DIR = "eval/corpus/teacher_writings"

      def initialize(backend: nil, judge: nil, synthesizer: nil)
        @backend = backend || Backends::FakeBackend.new
        @judge = judge || Judge.new(backend: @backend)
        @synthesizer = synthesizer # nil 이면 self-eval (expected_output 사용)
      end

      attr_reader :backend, :judge

      # 전체 corpus 순회 → 결과 payload 반환.
      # @return [Hash] {run_id, backend, model, corpus_size, summary, cases}
      def run(corpus_dir: DEFAULT_CORPUS_DIR, only_task: nil, limit: nil)
        cases = load_cases(corpus_dir)
        cases = cases.select { |c| c[:fm]["task"] == only_task.to_s } if only_task
        cases = cases.first(limit) if limit

        per_case = cases.map { |c| evaluate_case(c) }

        {
          "run_id" => Time.now.iso8601,
          "backend" => @backend.name,
          "model" => extract_model_name,
          "corpus_dir" => corpus_dir,
          "corpus_size" => cases.size,
          "filter" => {"task" => only_task, "limit" => limit}.compact,
          "summary" => build_summary(per_case),
          "cases" => per_case
        }
      end

      private

      def load_cases(corpus_dir)
        root = Pathname.new(corpus_dir).expand_path
        unless root.exist?
          # spec/지식: corpus 가 없으면 빈 배열 (graceful)
          return []
        end

        Dir.glob(root.join("**/*.md")).sort.map do |path|
          parsed = FrontMatterParser::Parser.new(:md).call(File.read(path))
          {
            path: path,
            fm: parsed.front_matter,
            body: parsed.content
          }
        end
      end

      def evaluate_case(case_data)
        llm_output = synthesize(case_data)
        scores = @judge.evaluate(case_data: case_data, llm_output: llm_output)
        {
          "case_id" => case_data[:fm]["case_id"],
          "task" => case_data[:fm]["task"],
          "scores" => scores
        }
      end

      def synthesize(case_data)
        if @synthesizer
          @synthesizer.call(case_data)
        else
          # self-eval: expected_output 을 그대로 LLM 출력으로 간주 → baseline 점수.
          format_expected(case_data[:fm]["expected_output"])
        end
      end

      def format_expected(expected)
        case expected
        when String then expected
        when Hash, Array then JSON.pretty_generate(expected)
        else expected.to_s
        end
      end

      def build_summary(per_case)
        # dimension → [scores] 모음 → 평균/min/max
        dim_scores = Hash.new { |h, k| h[k] = [] }
        per_case.each do |entry|
          entry["scores"].each do |dim, payload|
            dim_scores[dim] << payload["score"]
          end
        end

        dim_scores.transform_values do |scores|
          {
            "avg" => (scores.sum.to_f / scores.size).round(3),
            "min" => scores.min,
            "max" => scores.max,
            "n" => scores.size
          }
        end
      end

      def extract_model_name
        return "fake-baseline" if @backend.is_a?(Backends::FakeBackend)
        @backend.respond_to?(:model) ? @backend.model : @backend.name
      end
    end
  end
end
