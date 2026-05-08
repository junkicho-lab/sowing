# frozen_string_literal: true

# 일별 작성 통계 (W6-T01).
# entries에서 created_at 기준으로 일별 집계 — AggregateDailyStats가 야간/부팅/요청 시 재계산.
# 마크다운 SoT 원칙(CLAUDE.md 원칙 1) 준수: 본 테이블은 캐시이며 entries에서 항상 재구축 가능.
#
# date 컬럼은 KST 기준 YYYY-MM-DD 문자열 — 사전식 정렬이 곧 시간순.
Sequel.migration do
  change do
    create_table(:daily_stats) do
      String :date, primary_key: true # YYYY-MM-DD (KST)
      Integer :memos_count, default: 0, null: false
      Integer :notes_count, default: 0, null: false
      Integer :records_count, default: 0, null: false
      Integer :total_count, default: 0, null: false
      String :computed_at, null: false
    end
  end
end
