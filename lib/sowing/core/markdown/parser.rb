# frozen_string_literal: true

require "front_matter_parser"

module Sowing
  module Core
    module Markdown
      # 마크다운 텍스트 → frontmatter Hash + body String 분리.
      # front_matter_parser gem 래퍼.
      #
      # 동작:
      #   - frontmatter가 있으면 YAML로 파싱하여 Hash 반환
      #   - 없으면 빈 Hash + 전체 텍스트를 body로
      #   - 잘못된 YAML이면 gem이 raise (Psych::SyntaxError 등) → 그대로 전파
      class Parser
        # @param text [String] 마크다운 전체 텍스트
        # @return [ParsedDocument]
        # @raise [ArgumentError] text가 String이 아닌 경우
        def parse(text)
          unless text.is_a?(String)
            raise ArgumentError, "text는 String이어야 합니다 (받은 타입: #{text.class})"
          end

          result = FrontMatterParser::Parser.new(:md).call(text)
          ParsedDocument.new(
            frontmatter: result.front_matter || {},
            body: result.content || ""
          )
        end
      end
    end
  end
end
