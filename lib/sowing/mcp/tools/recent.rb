# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 모든 모드 통합 최근순 — list_memos 가 단일 모드만이라 별도 도구.
      # "최근 활동 알려줘" 같은 자연어 요청에 적합.
      class Recent < Base
        tool_name "recent"
        description "메모/필기/기록 통합 최근순 N건. mode 무관. created_at 내림차순."
        input_schema(
          properties: {
            limit: {
              type: "integer",
              minimum: 1,
              maximum: 50,
              description: "반환 건수. 기본 10."
            }
          }
        )

        def self.call(limit: 10, server_context: nil)
          entries = index_repo.recent_across(limit: limit)
          json_response({
            count: entries.size,
            limit: limit,
            entries: entries.map { |e| serialize_entry(e) }
          })
        end
      end
    end
  end
end
