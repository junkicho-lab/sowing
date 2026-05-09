# frozen_string_literal: true

module Sowing
  module Eval
    module Backends
      # 모든 LLM 백엔드의 공통 인터페이스 (W13-T02).
      #
      # Judge 는 본 인터페이스만 의존하므로 백엔드 교체 자유 — 같은 입력에 대해
      # OpenAI / Anthropic / Ollama / Fake 어느 것이든 동일하게 동작.
      #
      # 모든 구현은 chat(system:, user:) → String 을 만족.
      # 응답은 JSON 문자열을 그대로 반환 (Judge 가 파싱).
      class Base
        # @param system [String] system prompt
        # @param user   [String] user prompt
        # @return       [String] 모델 응답 텍스트 (JSON 문자열 권장)
        def chat(system:, user:)
          raise NotImplementedError, "#{self.class}#chat 미구현"
        end

        # 백엔드 식별자 (audit·진단용).
        def name
          self.class.name.split("::").last
        end
      end
    end
  end
end
