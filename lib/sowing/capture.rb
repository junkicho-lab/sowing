# frozen_string_literal: true

module Sowing
  # Bounded Context #1 — Capture (포착).
  #
  # 책임: 매일 떠오르는 생각·메모·음성·관찰의 최저 마찰 진입점.
  # 진입장벽 0, 분류 최소.
  #
  # 미래 도메인 (Stage 2 R2-T01 에서 신설):
  #   - Capture::Domain::Item — 현재 Memo 의 흡수 + subject + subtype
  #
  # 의존: Core (base). 다른 Bounded Context 어디에도 의존하지 않는 base layer.
  #
  # 외부 인터페이스 (Façade) — 다른 모듈은 본 메서드들만 사용. 내부 클래스
  # 직접 참조 금지 (bin/sowing-arch-check 가 검증).
  module Capture
    # Façade 메서드 — Stage 2 (R2) 부터 실제 구현.
    # 현재는 stub — Stage 1 의 인터페이스 정의만.

    # @param body [String]   메모 본문
    # @param subject [Symbol, nil] :person|:subject|:document|:identity (ADR-016)
    # @param subtype [Symbol, nil] :general|:book|:lecture|:emotion|:student (W26-T01)
    # @return [Capture::Domain::Item]
    def self.create_item(body:, subject: nil, subtype: nil, tags: [])
      raise NotImplementedError, "Stage 2 R2-T03 에 구현"
    end

    def self.find(id)
      raise NotImplementedError, "Stage 2 R2-T02 에 구현"
    end

    def self.recent(limit: 10)
      raise NotImplementedError, "Stage 2 R2-T02 에 구현"
    end
  end
end
