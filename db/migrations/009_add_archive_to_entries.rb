# frozen_string_literal: true

# Phase R Stage 3 R3-T05 — entries.archived_at + archive_reason 컬럼 추가 (ADR-017).
#
# 배경: ADR-017 — 사용자가 "이제 그만 보고싶다" 한 entry 를 영구 삭제 없이
# "이관" (졸업·이직·종료 등). 휴지통은 자동 30일 후 영구 삭제 위험 — Archive 는
# 30년 보존이 원칙 (CLAUDE.md 원칙 5).
#
# 동작:
#   - archived_at IS NULL  → 활성 entry (검색·합성기·view_recent 모두 노출)
#   - archived_at NOT NULL → 보관 (일상 회상 자동 제외, /archive 페이지에서만 노출)
#   - archive_reason 자유 텍스트 (예: "졸업한 학생", "퇴직 부서", "휴지통 정리")
#
# 컬럼 추가 + 인덱스 (active entry 조회 시 partial index 최적화 고려할 수도 있으나,
# MVP 는 전체 인덱스로 충분 — 30 년에 entries 10만 행 가정).

Sequel.migration do
  up do
    # archived_at: ISO8601 String (NULL 허용)
    # archive_reason: 자유 텍스트 (NULL 허용)
    run "ALTER TABLE entries ADD COLUMN archived_at TEXT"
    run "ALTER TABLE entries ADD COLUMN archive_reason TEXT"
    add_index :entries, :archived_at
  end

  down do
    archived_count = self[:entries].exclude(archived_at: nil).count
    if archived_count > 0
      raise "되돌릴 수 없음 — 보관된 entry #{archived_count}건 존재. " \
            "먼저 unarchive 후 시도."
    end

    drop_index :entries, :archived_at
    alter_table(:entries) do
      drop_column :archive_reason
      drop_column :archived_at
    end
  end
end
