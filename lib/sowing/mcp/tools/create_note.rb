# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 외부 에이전트가 필기 생성. 기존 CreateNote Use Case 재사용.
      class CreateNote < Base
        tool_name "create_note"
        description "Sowing 필기(note) 생성. 카테고리 4종(lessons/trainings/books/meetings) + 출처 필수."
        input_schema(
          properties: {
            title: {type: "string", description: "필기 제목 (필수)."},
            body: {type: "string", description: "필기 본문 (필수)."},
            category: {
              type: "string",
              enum: %w[lessons trainings books meetings],
              description: "수업/연수/도서/회의 중 하나."
            },
            source: {
              type: "string",
              description: "출처 (필수). 예: 책 제목, 연수 이름, 교과서 단원."
            },
            tags: {
              type: "array",
              items: {type: "string"},
              description: "태그 (선택)."
            }
          },
          required: %w[title body category source]
        )

        def self.call(title:, body:, category:, source:, tags: [], server_context: nil)
          result = Core::AuditLog.with_actor("agent") do
            UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
              title: title, body: body, category: category,
              source: source, tags: Array(tags)
            )
          end

          if result.success?
            indexed = index_repo.find(result.value!.id)
            json_response(serialize_entry(indexed))
          else
            error_response("CreateNote 실패: #{result.failure.inspect}")
          end
        end
      end
    end
  end
end
