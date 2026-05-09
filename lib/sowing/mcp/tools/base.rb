# frozen_string_literal: true

require "json"
require "mcp"

module Sowing
  module MCP
    module Tools
      # 모든 Sowing MCP 도구의 공통 베이스. ::MCP::Tool 을 상속하고 응답 포맷·repos 접근을
      # 일관시킨다. 결과는 JSON 직렬화하여 type=text 콘텐츠로 반환 — 에이전트가 파싱 가능.
      class Base < ::MCP::Tool
        class << self
          def index_repo
            Sowing::MCP.repositories[:index]
          end

          def vault_repo
            Sowing::MCP.repositories[:vault]
          end

          # 성공 응답 — Hash/Array 를 pretty JSON 으로 직렬화.
          def json_response(payload)
            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.pretty_generate(payload)
            }])
          end

          # 에러 응답 — text 한 줄 + error: true.
          def error_response(message)
            ::MCP::Tool::Response.new(
              [{type: "text", text: "Error: #{message}"}],
              error: true
            )
          end

          # IndexedEntry → 직렬화 Hash. 본문 없음 (read_entry 만 본문 포함).
          def serialize_entry(entry)
            {
              id: entry.id.to_s,
              mode: entry.mode.to_s,
              path: entry.path,
              title: entry.title,
              category: entry.category,
              source: entry.source,
              created_at: entry.created_at.iso8601,
              updated_at: entry.updated_at.iso8601,
              tags: entry.tags
            }.compact
          end
        end
      end
    end
  end
end
