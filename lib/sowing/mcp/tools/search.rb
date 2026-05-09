# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 본문·제목 검색 (FTS5 trigram + 한국어 LIKE 폴백 자동 라우팅, W4-T02).
      # 모드/카테고리/태그 필터 지원.
      class Search < Base
        tool_name "search"
        description "Sowing 본문·제목 검색. 한국어 자동 라우팅 (3+자 FTS5, 2자는 LIKE). 결과는 created_at 내림차순. 본문 미포함."
        input_schema(
          properties: {
            q: {
              type: "string",
              description: "검색 쿼리 (필수, 비어 있으면 에러)."
            },
            mode: {
              type: "string",
              enum: %w[memo note record],
              description: "특정 mode 만 검색."
            },
            category: {
              type: "string",
              description: "카테고리 정확 일치 필터."
            },
            tag: {
              type: "string",
              description: "태그 필터 (case-insensitive)."
            },
            limit: {
              type: "integer",
              minimum: 1,
              maximum: 50,
              description: "반환 건수 (1~50, 기본 20)."
            }
          },
          required: ["q"]
        )

        def self.call(q:, mode: nil, category: nil, tag: nil, limit: 20, server_context: nil)
          query = q.to_s.strip
          return error_response("q (검색어) 가 비어 있습니다") if query.empty?

          mode_sym = mode&.to_sym
          if mode_sym && !%i[memo note record].include?(mode_sym)
            return error_response("지원하지 않는 mode: #{mode.inspect}")
          end

          entries = index_repo.search_with_filters(
            q: query,
            mode: mode_sym,
            category: category,
            tag: tag,
            limit: limit
          )

          json_response({
            query: query,
            filters: {mode: mode, category: category, tag: tag}.compact,
            count: entries.size,
            entries: entries.map { |e| serialize_entry(e) }
          })
        end
      end
    end
  end
end
