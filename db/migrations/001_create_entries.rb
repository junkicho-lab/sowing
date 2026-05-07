# frozen_string_literal: true

# entries 테이블: 모든 마크다운 파일의 메타 인덱스.
# 콘텐츠는 마크다운 파일에 있고, 본 테이블은 검색·정렬·필터를 위한 인덱스.

Sequel.migration do
  change do
    create_table(:entries) do
      String :id, primary_key: true # ULID
      String :path, null: false, unique: true
      String :mode, null: false # memo | note | record
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
      index :mode
      index :created_at
      index :category
    end
  end
end
