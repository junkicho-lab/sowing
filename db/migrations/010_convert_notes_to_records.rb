# frozen_string_literal: true

# Phase R Stage 5 R5-T01 — entries.mode='note' → 'record' 데이터 변환 (ADR-015).
#
# 배경: ADR-015 "Note 폐지" — 옛 Note 와 Record 의 의도 차이 (외부 자료 정리 vs
# 자기 경험·통찰) 만으로는 별도 mode 가 정당화되지 않음. Knowledge::Record 가
# Note 의 source 까지 흡수한 superset 이므로 데이터 일원화 가능.
#
# 본 마이그레이션이 하는 일:
#   1. 모든 entries.mode='note' 행을 mode='record' 로 변환.
#   2. path 컬럼의 20_Notes/{category}/ 부분을 30_Records/{YYYY}/{category}/ 로
#      재작성 (실제 파일 이동은 별도 vault task — 본 마이그레이션은 DB 만).
#   3. CHECK 제약은 그대로 (memo|note|record|plan) — 옛 코드가 새 note 를 만들 수
#      있도록 호환 유지. CHECK 에서 'note' 제거는 별도 마이그레이션 011 (코드
#      제거와 동기화).
#
# 멱등성:
#   - 이미 'note' 행이 0건이면 UPDATE 영향 0 — 안전 재실행.
#   - path 갱신은 정규식 기반 — 이미 변환된 path 에 다시 적용해도 변화 없음.
#
# down:
#   - 되돌리기 불가 — note ↔ record 구분 정보가 source 컬럼에 남아 있지 않으면
#     (Note 는 source 가 있을 수 있고 없을 수도 있음) 모호. 데이터 손실 위험.
#   - 따라서 down 은 명시적으로 거부.

Sequel.migration do
  up do
    note_count = self[:entries].where(mode: "note").count
    next if note_count.zero?

    transaction do
      # path 재작성 — Sequel 의 표현식으로 동적 path 변환.
      # 20_Notes/{cat}/{file}.md → 30_Records/{YYYY}/{cat}/{file}.md
      # {YYYY} 는 created_at 의 앞 4자리.
      #
      # SQLite SUBSTR + REPLACE 로 표현:
      #   REPLACE(path, '20_Notes/', '30_Records/' || SUBSTR(created_at, 1, 4) || '/')
      run <<~SQL
        UPDATE entries
        SET path = REPLACE(path,
          '20_Notes/',
          '30_Records/' || SUBSTR(created_at, 1, 4) || '/'),
          mode = 'record'
        WHERE mode = 'note'
      SQL
    end
  end

  down do
    raise "되돌릴 수 없음 — Note 와 Record 의 구분 정보 손실. " \
          "Git 으로 마이그레이션 010 이전 시점 DB 백업에서 복원하세요 " \
          "(CLAUDE.md 원칙 5 — 영구 삭제 0)."
  end
end
