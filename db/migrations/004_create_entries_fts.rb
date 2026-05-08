# frozen_string_literal: true

# FTS5 가상 테이블 — 한국어 부분일치를 위해 trigram 토크나이저 사용 (SQLite 3.34+).
#
# 본문 body는 entries 테이블에 없으므로 (SoT는 마크다운 파일) IndexRepo가
# upsert 시점에 명시적으로 sync_fts로 채운다.
#
# trigram 한계: 3글자 이상 매칭만. 한국어 2글자 query는 W4-T02 LIKE 폴백에서 보강.
# CLAUDE.md 원칙 1 호환: entries_fts.body는 검색용 캐시이며 마크다운에서 재구축 가능.

Sequel.migration do
  up do
    run <<~SQL
      CREATE VIRTUAL TABLE entries_fts USING fts5(
        id UNINDEXED,
        title,
        body,
        tokenize = 'trigram'
      )
    SQL
  end

  down do
    run "DROP TABLE entries_fts"
  end
end
