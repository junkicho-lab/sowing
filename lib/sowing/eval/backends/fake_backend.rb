# frozen_string_literal: true

require "json"

module Sowing
  module Eval
    module Backends
      # 결정적 응답 백엔드 — CI / 단위 테스트 / 오프라인 환경 (W13-T02).
      #
      # 사용:
      #   FakeBackend.new(responses: ["{\"factuality\":{\"score\":4,...}}"])
      #
      # 호출마다 responses[i] 반환. responses 가 다 떨어지면 default_response.
      # default_response 는 평가 차원 모두에 score=3 reason="(fake) baseline" 부여.
      class FakeBackend < Base
        def initialize(responses: nil, default_response: nil)
          @responses = Array(responses)
          @default = default_response || self.class.baseline_json
          @call_count = 0
          @captured_prompts = []
        end

        attr_reader :captured_prompts, :call_count

        def chat(system:, user:)
          @captured_prompts << {system: system, user: user}
          response = @responses[@call_count] || @default
          @call_count += 1
          response
        end

        # 모든 차원 score=3 (중간), reason 명시. Judge 의 기본 기대 응답과 호환.
        def self.baseline_json
          payload = Sowing::Eval::Judge::ALL_DIMENSIONS.to_h do |dim|
            [dim, {"score" => 3, "reason" => "(fake) baseline"}]
          end
          JSON.generate(payload)
        end
      end
    end
  end
end
