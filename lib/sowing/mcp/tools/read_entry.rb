# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 단일 entry 의 본문까지 포함하여 조회. id 또는 path 둘 중 하나 필수.
      class ReadEntry < Base
        tool_name "read_entry"
        description "단일 entry 의 frontmatter + 본문 전체 반환. id 또는 path 둘 중 하나 필수."
        input_schema(
          properties: {
            id: {
              type: "string",
              description: "ULID (예: 01KR1SAMP00000000000000001)."
            },
            path: {
              type: "string",
              description: "vault 기준 상대 경로 (예: 00_Inbox/2026-05-08_092314.md)."
            }
          }
        )

        def self.call(id: nil, path: nil, server_context: nil)
          if id.to_s.strip.empty? && path.to_s.strip.empty?
            return error_response("id 또는 path 중 하나는 반드시 제공해야 합니다")
          end

          indexed = id ? index_repo.find(id) : index_repo.find_by_path(path)
          return error_response("entry 를 찾을 수 없습니다 (id=#{id.inspect}, path=#{path.inspect})") if indexed.nil?

          domain = begin
            vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            return error_response("파일이 누락되었습니다: #{indexed.path} (인덱스만 있고 마크다운 파일 없음)")
          end

          json_response({
            id: indexed.id.to_s,
            mode: indexed.mode.to_s,
            path: indexed.path,
            title: domain.title,
            category: domain.respond_to?(:category) ? domain.category : nil,
            source: domain.respond_to?(:source) ? domain.source : nil,
            tags: domain.tags.to_a,
            promoted_from: domain.respond_to?(:promoted_from) ? domain.promoted_from : nil,
            created_at: domain.created_at.iso8601,
            updated_at: domain.updated_at.iso8601,
            body: domain.body
          }.compact)
        end
      end
    end
  end
end
