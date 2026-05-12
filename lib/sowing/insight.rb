# frozen_string_literal: true

module Sowing
  # Bounded Context #3 — Insight (통찰·합성).
  #
  # 책임: 17 합성기 + 자기 거울 5축. ADR-013 자율 mutation 0 —
  # 모든 합성 결과는 `.sowing/synth/` 검토 대기 폴더, 사용자 수락 클릭으로만
  # 정식 기록 이동.
  #
  # 미래 도메인 (Stage 4a R4a-T01 에서 신설):
  #   - Insight::Domain::Synthesis — 통합 도메인 (type/source/body/status)
  #   - Insight::Synthesizer::* — 17 종 (학생디제스트·학기회고·자기거울 등)
  #
  # 의존: Core. Knowledge 의 entries 조회 (단방향).
  module Insight
    # Stage 4a (R4a) 부터 실제 구현. 현재는 stub.

    # 17 합성기 type 목록 (Stage 4a 에서 namespace 이전).
    SYNTHESIZER_TYPES = %w[
      students lessons reflections patterns contradictions
      consultations assessments trainings weekly orphans
      lesson-series tag-clusters seasonal parent-patterns
      self-patterns learning-progress event-causality self-mirror
    ].freeze

    def self.generate(type:, **params)
      raise NotImplementedError, "Stage 4a R4a-T02 에 구현"
    end

    def self.pending_count
      raise NotImplementedError, "Stage 4a R4a-T03 에 구현"
    end

    def self.accept(synth_id)
      raise NotImplementedError, "Stage 4a 에 구현"
    end

    def self.reject(synth_id)
      raise NotImplementedError, "Stage 4a 에 구현"
    end
  end
end
