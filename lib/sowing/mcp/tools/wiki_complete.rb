# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 위키링크 자동완성 — IndexRepo#complete (ADR-004).
      # title substring 매칭. 메모는 title 이 nil 이라 매칭 제외.
      # 외부 에이전트가 "[[협동학습 으로 시작하는 필기 후보 알려줘" 시 호출.
      class WikiComplete < Base
        tool_name "wiki_complete"
        description "위키링크 후보 검색. q 가 비어 있으면 모드 우선(record→note) + 최근순. note/record 만 매칭 (memo 는 title 없음)."
        input_schema(
          properties: {
            q: {
              type: "string",
              description: "title 부분 매칭. 빈 문자열 허용 (전체 후보)."
            },
            limit: {
              type: "integer",
              minimum: 1,
              maximum: 100,
              description: "최대 후보 수. 기본 25."
            }
          }
        )

        def self.call(q: "", limit: 25, server_context: nil)
          rows = index_repo.complete(q: q.to_s, limit: limit)
          json_response({
            query: q.to_s,
            count: rows.size,
            candidates: rows.map { |row|
              {
                id: row[:id],
                mode: row[:mode],
                title: row[:title],
                path: row[:path]
              }
            }
          })
        end
      end
    end
  end
end
