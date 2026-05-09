# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 태그 클라우드 — 모든 태그 사용 횟수 desc.
      # 외부 에이전트가 "자주 쓰는 태그 보여줘" 시 호출.
      class TagCloud < Base
        tool_name "tag_cloud"
        description "사용된 모든 태그를 사용 빈도 내림차순으로 반환. limit 으로 상위 N개만."
        input_schema(
          properties: {
            limit: {
              type: "integer",
              minimum: 1,
              maximum: 200,
              description: "상위 N개. 기본 50."
            }
          }
        )

        def self.call(limit: 50, server_context: nil)
          tags = index_repo.tag_cloud.first(limit)
          json_response({
            count: tags.size,
            limit: limit,
            tags: tags.map { |t| {name: t[:name], count: t[:count]} }
          })
        end
      end
    end
  end
end
