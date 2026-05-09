# frozen_string_literal: true

require "json"

module Sowing
  module Eval
    # LLM-judge — case + LLM 출력 → 차원별 점수 0~5 (W13-T02).
    #
    # 책임:
    #   - 평가 prompt 합성 (system + user)
    #   - 백엔드 호출 (주입된 Backends::Base)
    #   - 응답 JSON 파싱 → {dimension: {score:, reason:}} 정규화
    #   - 잘못된 응답에 대해 graceful fallback (0점 + reason)
    #
    # 사용:
    #   judge = Judge.new(backend: Backends::OpenAI.new)
    #   result = judge.evaluate(case_data: case_hash, llm_output: "...")
    #   # => {factuality: {score: 4, reason: "..."}, coverage: {...}}
    class Judge
      # SCHEMA.md §4 의 12 차원. 변경 시 SCHEMA.md 도 함께 갱신.
      ALL_DIMENSIONS = %w[
        factuality coverage conciseness relevance format
        korean_consistency tone precision recall evidence
        insight structure
      ].freeze

      def initialize(backend: nil)
        @backend = backend || Backends::FakeBackend.new
      end

      attr_reader :backend

      # @param case_data [Hash] {fm: front_matter, body: input, expected_output: ...}
      #   typically corpus_spec 의 cases 한 건.
      # @param llm_output [String] 평가할 LLM 합성 결과
      # @return [Hash] {dimension_str => {"score" => Integer 0~5, "reason" => String}}
      def evaluate(case_data:, llm_output:)
        dims = case_data.dig(:fm, "eval_dimensions") || case_data.dig("eval_dimensions") || ALL_DIMENSIONS
        system = system_prompt(dims)
        user = user_prompt(case_data, llm_output, dims)

        raw = @backend.chat(system: system, user: user)
        parse_response(raw, dims)
      end

      private

      def system_prompt(dimensions)
        <<~TXT
          You are a strict grader for Korean teacher writing assistants.
          Score the LLM output on these dimensions: #{dimensions.join(", ")}.
          Each score 0~5 (5=excellent). Provide a one-sentence Korean reason.
          Respond ONLY with a JSON object — keys are dimension names, values are
          {"score": <int 0-5>, "reason": "<Korean string>"}. No prose outside JSON.
        TXT
      end

      def user_prompt(case_data, llm_output, dimensions)
        body = case_data[:body] || case_data["body"] || ""
        expected = case_data.dig(:fm, "expected_output") || case_data.dig("expected_output")
        <<~TXT
          # Task
          #{case_data.dig(:fm, "task") || case_data.dig("task")}

          # Input (teacher's writing)
          ```
          #{body}
          ```

          # Expected output (gold standard)
          ```
          #{format_expected(expected)}
          ```

          # LLM output to evaluate
          ```
          #{llm_output}
          ```

          # Dimensions to score
          #{dimensions.map { |d| "- #{d}" }.join("\n")}
        TXT
      end

      def format_expected(expected)
        case expected
        when String then expected
        when Hash, Array then JSON.pretty_generate(expected)
        else expected.to_s
        end
      end

      def parse_response(raw, dimensions)
        parsed =
          begin
            JSON.parse(raw)
          rescue JSON::ParserError
            return fallback_scores(dimensions, "JSON 파싱 실패: #{raw[0, 100]}")
          end

        dimensions.each_with_object({}) do |dim, acc|
          entry = parsed[dim] || parsed[dim.to_s]
          acc[dim] = if entry.is_a?(Hash) && entry.key?("score")
            {
              "score" => clamp_score(entry["score"]),
              "reason" => entry["reason"].to_s
            }
          else
            {"score" => 0, "reason" => "응답에 #{dim} 누락"}
          end
        end
      end

      def fallback_scores(dimensions, reason)
        dimensions.to_h { |d| [d, {"score" => 0, "reason" => reason}] }
      end

      def clamp_score(value)
        score = value.to_i
        score.clamp(0, 5)
      end
    end
  end
end
