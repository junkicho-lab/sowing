# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 외부 에이전트가 기록 생성. 기존 CreateRecord Use Case 재사용.
      # 카테고리 자유 텍스트 (학급운영, 평가, 회고 등).
      class CreateRecord < Base
        tool_name "create_record"
        description "Sowing 기록(record) 생성. 카테고리 자유 텍스트 (학급운영/평가/회고 등). 30_Records/{YYYY}/{category}/ 에 저장."
        input_schema(
          properties: {
            title: {type: "string", description: "기록 제목 (필수)."},
            body: {type: "string", description: "기록 본문 (필수)."},
            category: {
              type: "string",
              description: "카테고리 자유 텍스트 (예: 학급운영, 평가, 수업회고)."
            },
            tags: {
              type: "array",
              items: {type: "string"},
              description: "태그 (선택)."
            }
          },
          required: %w[title body category]
        )

        def self.call(title:, body:, category:, tags: [], server_context: nil)
          result = Infrastructure::AuditLog.with_actor("agent") do
            UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo).call(
              title: title, body: body, category: category, tags: Array(tags)
            )
          end

          if result.success?
            indexed = index_repo.find(result.value!.id)
            json_response(serialize_entry(indexed))
          else
            error_response("CreateRecord 실패: #{result.failure.inspect}")
          end
        end
      end
    end
  end
end
