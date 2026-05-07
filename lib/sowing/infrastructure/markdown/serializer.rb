# frozen_string_literal: true

require "yaml"

module Sowing
  module Infrastructure
    module Markdown
      # 도메인 객체 또는 Hash+body → 옵시디언 호환 마크다운 문자열.
      #
      # 두 가지 진입점:
      #   - serialize(entry)              — Domain::Memo/Note/Record 도메인에 위임
      #   - build(frontmatter_hash, body) — 임의 Hash + body 직접 직렬화
      # 두 경로 모두 동일한 바이트 출력을 보장 (Parser 라운드트립 spec으로 검증).
      class Serializer
        # @param entry [Sowing::Domain::Memo, Note, Record]
        # @return [String] frontmatter + 본문 마크다운
        def serialize(entry)
          entry.to_markdown
        end

        # @param frontmatter [Hash] frontmatter 키-값 (nil 값 키는 호출 측에서 .compact 권장)
        # @param body        [String]
        # @return [String]
        def build(frontmatter, body)
          unless frontmatter.is_a?(Hash)
            raise ArgumentError, "frontmatter는 Hash여야 합니다 (받은 타입: #{frontmatter.class})"
          end
          unless body.is_a?(String)
            raise ArgumentError, "body는 String이어야 합니다 (받은 타입: #{body.class})"
          end

          yaml_body = YAML.dump(frontmatter).delete_prefix("---\n")
          body_text = body.sub(/\n+\z/, "")
          "---\n#{yaml_body}---\n\n#{body_text}\n"
        end
      end
    end
  end
end
