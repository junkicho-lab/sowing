# frozen_string_literal: true

# 위키링크 그래프 인덱스 (SPEC §8.3).
# - source_id: 링크를 가진 entry (CASCADE — entry 삭제 시 자기 링크 모두 제거)
# - target_id: 가리키는 entry. NULL이면 broken (SET NULL — 삭제된 entry로의 링크는 자동 broken 처리)
# - target_text: [[…]] 안의 raw 텍스트. 인덱스 생성 후에도 사용자 의도 보존 → 깨진 링크 추적 + 추후 re-link 가능

Sequel.migration do
  change do
    create_table(:links) do
      foreign_key :source_id, :entries, type: String, null: false, on_delete: :cascade
      foreign_key :target_id, :entries, type: String, null: true, on_delete: :set_null
      String :target_text, null: false
      primary_key [:source_id, :target_text]
      index :target_id
      index :target_text
    end
  end
end
