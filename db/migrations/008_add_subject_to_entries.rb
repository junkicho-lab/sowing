# frozen_string_literal: true

# Phase R Stage 2 R2-T05 — entries.subject 컬럼 추가 (ADR-016 4축).
#
# 배경: 비전 D.1 "쓰기" 단계에서 subject 4축 명시 분류 (person/subject/document/identity)
# 부착 가능. Capture::Item 이 R2-T01 부터 도메인에서는 지원하지만, IndexRepo 가
# 인덱스 컬럼 부재로 filter·검색 불가. 본 마이그레이션이 그 gap 해소.
#
# SQLite 특성:
#   - ALTER TABLE ADD COLUMN 으로 CHECK 제약 inline 부착 가능 (3.30+ 지원).
#   - 기존 모든 행은 subject=NULL → CHECK 통과 (NULL OR ... 형식).
#   - 따라서 table recreate 불필요 (마이그레이션 007 의 무거운 패턴 회피).
#
# DOWN 전략:
#   - SQLite 3.35.0+ 의 ALTER TABLE DROP COLUMN 사용.
#   - 인덱스 먼저 drop 후 컬럼 drop.
#
# IndexRepo·Item 측 영향:
#   - IndexRepo.ENTRY_COLUMNS / build_row / to_indexed_entry 에 :subject 추가
#   - IndexedEntry Data 클래스에 :subject 필드 추가
#   - 위 변경은 본 마이그레이션과 같은 PR 에서 수행 (R2-T05 일괄)

Sequel.migration do
  up do
    # CHECK: NULL (분류 안 한 capture) 또는 4축 중 하나
    run <<~SQL
      ALTER TABLE entries ADD COLUMN subject TEXT
        CHECK (subject IS NULL OR subject IN ('person', 'subject', 'document', 'identity'))
    SQL

    add_index :entries, :subject
  end

  down do
    # 4축 데이터 손실 경고
    subject_count = self[:entries].exclude(subject: nil).count
    if subject_count > 0
      raise "되돌릴 수 없음 — subject 가 부착된 행 #{subject_count}건 존재. " \
            "먼저 4축 분류 백업 후 시도."
    end

    drop_index :entries, :subject
    alter_table(:entries) { drop_column :subject }
  end
end
