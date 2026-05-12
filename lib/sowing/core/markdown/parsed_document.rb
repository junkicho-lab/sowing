# frozen_string_literal: true

module Sowing
  module Core
    module Markdown
      # 마크다운을 파싱한 결과: frontmatter (Hash) + body (String).
      # 불변 (frozen). Domain 객체로 변환하기 전 raw 데이터 컨테이너.
      class ParsedDocument
        attr_reader :frontmatter, :body

        # @param frontmatter [Hash] YAML frontmatter (없으면 빈 Hash)
        # @param body        [String] 본문 (없으면 빈 문자열)
        def initialize(frontmatter:, body:)
          unless frontmatter.is_a?(Hash)
            raise ArgumentError, "frontmatter는 Hash여야 합니다 (받은 타입: #{frontmatter.class})"
          end
          unless body.is_a?(String)
            raise ArgumentError, "body는 String이어야 합니다 (받은 타입: #{body.class})"
          end

          @frontmatter = frontmatter.freeze
          @body = body.freeze
          freeze
        end
      end
    end
  end
end
