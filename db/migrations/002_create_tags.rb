# frozen_string_literal: true

# 태그 정규화 테이블 + entries↔tags 다대다 매핑.
# tags.name은 COLLATE NOCASE로 case-insensitive uniqueness 보장 (TagSet 정책과 정합).

Sequel.migration do
  change do
    create_table(:tags) do
      primary_key :id
      String :name, null: false, unique: true, collate: "NOCASE"
    end

    create_table(:entry_tags) do
      foreign_key :entry_id, :entries, type: String, null: false, on_delete: :cascade
      foreign_key :tag_id, :tags, type: Integer, null: false, on_delete: :cascade
      primary_key [:entry_id, :tag_id]
      index :tag_id
    end
  end
end
