# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 외부 에이전트가 메모 생성. 기존 CreateMemo Use Case 재사용.
      # AuditLog.with_actor("agent") 로 감싸 mutation 이 actor=agent 로 기록됨.
      class CreateMemo < Base
        tool_name "create_memo"
        description "Sowing 메모(memo) 생성. 본문 한 줄~여러 줄. audit log 에 actor=agent 로 자동 기록."
        input_schema(
          properties: {
            body: {
              type: "string",
              description: "메모 본문 (필수, 빈 문자열 거부)."
            },
            tags: {
              type: "array",
              items: {type: "string"},
              description: "태그 목록 (선택). frontmatter tags 에 저장."
            }
          },
          required: ["body"]
        )

        def self.call(body:, tags: [], server_context: nil)
          return error_response("body 가 비어있습니다") if body.to_s.strip.empty?

          result = Core::AuditLog.with_actor("agent") do
            UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
              .call(body: body, tags: Array(tags))
          end

          if result.success?
            indexed = index_repo.find(result.value!.id)
            json_response(serialize_entry(indexed))
          else
            error_response("CreateMemo 실패: #{result.failure.inspect}")
          end
        end
      end
    end
  end
end
