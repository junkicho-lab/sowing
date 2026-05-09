# frozen_string_literal: true

module Sowing
  # Eval Infrastructure (Phase 10).
  #
  # 책임:
  #   - LLM 출력을 결정적으로 채점 (Judge)
  #   - OpenAI/Anthropic/Ollama 백엔드 추상화 (Backends)
  #   - 사람-judge 일치 측정 (Kappa)
  #
  # Phase 11~12 의 LLM 합성 기능은 본 인프라 위에 얹는다.
  # ADR-013: Phase 9 → 10 → 11 → 12 순서 의무.
  module Eval
  end
end
