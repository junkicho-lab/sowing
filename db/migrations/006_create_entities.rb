# frozen_string_literal: true

# Phase 11 EntityExtractor 용 테이블 (W17-T01).
#
# entities: 학생·과목·위치 등 entry 본문에서 추출된 엔티티.
#   - type+name 유일 (같은 학생 1 row).
#   - mention_count 누적.
#   - first_seen_at / last_seen_at 으로 활동 시간 추적.
#
# entity_mentions: entity ↔ entry 다대다 매핑 (인용 출처).
#   - StudentDigest 합성 시 어느 entry 에서 언급됐는지 cite 가능.
#   - position 은 본문 내 글자 offset (선택, 향후 highlight 용).
#
# CLAUDE.md 원칙 1 (마크다운 SoT): 본 테이블은 캐시 — entries 에서 재구축 가능.
Sequel.migration do
  change do
    create_table(:entities) do
      primary_key :id
      String :type, null: false # 'student' | 'subject' | 'location'
      String :name, null: false
      String :first_seen_at, null: false
      String :last_seen_at, null: false
      Integer :mention_count, default: 0, null: false

      check { type =~ %w[student subject location] }
      unique [:type, :name]
      index :type
    end

    create_table(:entity_mentions) do
      primary_key :id
      foreign_key :entity_id, :entities, on_delete: :cascade, null: false
      String :entry_id, null: false # entries.id (ULID, FK 아님 — 외부 변경 동기화 단순화)
      Integer :position # 본문 글자 offset (선택)
      index :entity_id
      index :entry_id
    end
  end
end
