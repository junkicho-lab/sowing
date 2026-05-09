# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 최근 entries 목록 (mode 필터, 페이징 지원).
      # 외부 에이전트가 "최근 메모 5건" 같은 자연어 요청 시 호출.
      class ListMemos < Base
        tool_name "list_memos"
        description "Sowing 의 최근 entries 를 mode 별로 조회. created_at 내림차순. 본문 미포함 — 본문은 read_entry 사용."
        input_schema(
          properties: {
            mode: {
              type: "string",
              enum: %w[memo note record],
              description: "조회할 entry 모드. 기본 memo."
            },
            limit: {
              type: "integer",
              minimum: 1,
              maximum: 100,
              description: "반환 건수 (1~100, 기본 30)."
            },
            offset: {
              type: "integer",
              minimum: 0,
              description: "건너뛸 건수 (페이지네이션용)."
            }
          }
        )

        def self.call(mode: "memo", limit: 30, offset: 0, server_context: nil)
          mode_sym = mode.to_sym
          unless %i[memo note record].include?(mode_sym)
            return error_response("지원하지 않는 mode: #{mode.inspect} (memo|note|record)")
          end

          entries = index_repo.list(mode: mode_sym, limit: limit, offset: offset)
          json_response({
            mode: mode,
            count: entries.size,
            limit: limit,
            offset: offset,
            entries: entries.map { |e| serialize_entry(e) }
          })
        end
      end
    end
  end
end
