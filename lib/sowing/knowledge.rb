# frozen_string_literal: true

module Sowing
  # Bounded Context #2 — Knowledge (지식·기록).
  #
  # 책임: 정리된 노트·체계적 기록·계획 + Archive (이관) 관리.
  # subject 4축 명시 분류 + 자유 카테고리 공존.
  #
  # 미래 도메인 (Stage 3 R3-T01·T02 에서 신설):
  #   - Knowledge::Domain::Record — Note + Record 흡수 (ADR-015)
  #   - Knowledge::Domain::Plan — 5 period (daily/weekly/monthly/project/semester)
  #
  # Archive (ADR-017): archived_at + archive_reason 메타데이터.
  # 일상 회상 (검색·합성기·view_recent) 에서 자동 제외, 보관함 (`/archive`)
  # 페이지에서만 노출.
  #
  # 의존: Core. Capture 의 promote 진입을 받음 (단방향).
  module Knowledge
    # Stage 3 (R3) 부터 실제 구현. 현재는 stub.

    def self.create_record(title:, body:, category:, subject: nil, **opts)
      raise NotImplementedError, "Stage 3 R3-T01 에 구현"
    end

    def self.create_plan(title:, period:, plan_date:, body: "", subject: nil, **opts)
      raise NotImplementedError, "Stage 3 R3-T02 에 구현"
    end

    def self.archive(entry_id, reason:)
      raise NotImplementedError, "Stage 3 R3-T05 에 구현 (ADR-017)"
    end

    def self.unarchive(entry_id)
      raise NotImplementedError, "Stage 3 R3-T05 에 구현"
    end
  end
end
