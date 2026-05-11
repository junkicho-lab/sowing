# frozen_string_literal: true

# Phase 13 W27-T03 — entries.mode CHECK 제약에 'plan' 추가.
#
# 배경: W27-T01 에서 Plan 도메인 신설 했지만 PlanRepo 가 파일 시스템에만 저장.
# 본 마이그레이션으로 entries 테이블에도 통합 → recent_across / /view/recent /
# 검색·인덱스 모두 plan 도 1급 시민.
#
# SQLite 의 CHECK constraint 는 ALTER TABLE 로 변경 불가. table recreate 패턴:
#   1. entries_v2 만들기 (CHECK 갱신, 동일 columns·indexes)
#   2. INSERT INTO entries_v2 SELECT * FROM entries
#   3. DROP TABLE entries
#   4. RENAME entries_v2 → entries
#   5. 인덱스 재생성
#
# entries_fts 는 별도 가상 테이블 — 트리거 없음, IndexRepo 가 명시 sync — 영향 없음.

Sequel.migration do
  up do
    # foreign_keys 일시 비활성 (entries 가 다른 테이블에서 참조될 수도 있음 — 본 시점엔 없지만 안전망)
    run "PRAGMA foreign_keys=off"

    transaction do
      # 1. 새 테이블 — CHECK 에 plan 추가, 그 외 동일
      create_table(:entries_v2) do
        String :id, primary_key: true
        String :path, null: false, unique: true
        String :mode, null: false
        String :title
        String :category
        String :template
        String :source
        String :promoted_from
        String :created_at, null: false
        String :updated_at, null: false
        Integer :file_mtime, null: false
        String :file_hash, null: false
        Integer :word_count, default: 0
        String :indexed_at, null: false

        check { mode =~ %w[memo note record plan] }
      end

      # 2. 데이터 이전
      run "INSERT INTO entries_v2 SELECT * FROM entries"

      # 3. 옛 테이블 삭제 + rename
      drop_table(:entries)
      rename_table(:entries_v2, :entries)

      # 4. 인덱스 재생성 (원본 001 의 3개 인덱스)
      add_index :entries, :mode
      add_index :entries, :created_at
      add_index :entries, :category
    end

    run "PRAGMA foreign_keys=on"
  end

  down do
    # 되돌리기 — plan entries 가 있으면 거부 (데이터 손실 방지)
    plan_count = self[:entries].where(mode: "plan").count
    raise "되돌릴 수 없음 — entries 테이블에 plan mode #{plan_count}건 존재. " \
          "먼저 PlanRepo 로 정리 후 시도." if plan_count > 0

    run "PRAGMA foreign_keys=off"
    transaction do
      create_table(:entries_v1) do
        String :id, primary_key: true
        String :path, null: false, unique: true
        String :mode, null: false
        String :title
        String :category
        String :template
        String :source
        String :promoted_from
        String :created_at, null: false
        String :updated_at, null: false
        Integer :file_mtime, null: false
        String :file_hash, null: false
        Integer :word_count, default: 0
        String :indexed_at, null: false
        check { mode =~ %w[memo note record] }
      end
      run "INSERT INTO entries_v1 SELECT * FROM entries"
      drop_table(:entries)
      rename_table(:entries_v1, :entries)
      add_index :entries, :mode
      add_index :entries, :created_at
      add_index :entries, :category
    end
    run "PRAGMA foreign_keys=on"
  end
end
