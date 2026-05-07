# frozen_string_literal: true

require "yaml"

module Sowing
  module Domain
    # Memo/Note/Record 공통 동작 mixin.
    #
    # 포함 클래스가 정의해야 하는 것:
    #   - mode  (Symbol; 예: :memo, :note, :record)
    #   - body  (String; attr_reader)
    #   - to_frontmatter (Hash; nil 값 키는 .compact 로 제외)
    #   - common_frontmatter 호출에 필요한 attr들 (id, title, tags, template, created_at, updated_at)
    #
    # 본 모듈이 제공:
    #   - common_frontmatter — 7개 공통 키의 Hash
    #   - to_markdown        — frontmatter + body의 옵시디언 호환 마크다운 문자열
    #   - validate_*!        — 타입 검증 helpers (private)
    module Entry
      # 공통 frontmatter 키 7개를 Hash로 반환.
      # 각 도메인 클래스의 to_frontmatter 는 본 결과에 자신만의 키를 merge 한 뒤 .compact 한다.
      def common_frontmatter
        {
          "id" => id.to_s,
          "mode" => mode.to_s,
          "title" => title,
          "tags" => tags.to_a,
          "template" => template,
          "created_at" => created_at.iso8601,
          "updated_at" => updated_at.iso8601
        }
      end

      # 마크다운 직렬화: YAML frontmatter + 본문.
      # 옵시디언이 그대로 인식 가능한 표준 형식 (---로 둘러싼 frontmatter, 빈 줄, 본문).
      def to_markdown
        yaml_body = YAML.dump(to_frontmatter).delete_prefix("---\n")
        body_text = body.sub(/\n+\z/, "")
        "---\n#{yaml_body}---\n\n#{body_text}\n"
      end

      private

      def validate_ulid!(value, name)
        return if value.is_a?(ValueObjects::Ulid)
        raise ArgumentError,
          "#{name}는(은) Sowing::Domain::ValueObjects::Ulid 인스턴스여야 합니다 (받은 타입: #{value.class})"
      end

      def validate_string!(value, name)
        return if value.is_a?(String)
        raise ArgumentError,
          "#{name}는(은) String이어야 합니다 (받은 타입: #{value.class})"
      end

      def validate_optional_string!(value, name)
        return if value.nil?
        validate_string!(value, name)
      end

      def validate_tag_set!(value)
        return if value.is_a?(ValueObjects::TagSet)
        raise ArgumentError,
          "tags는 Sowing::Domain::ValueObjects::TagSet 인스턴스여야 합니다 (받은 타입: #{value.class})"
      end

      def validate_time!(value, name)
        return if value.is_a?(Time)
        raise ArgumentError,
          "#{name}는(은) Time 인스턴스여야 합니다 (받은 타입: #{value.class})"
      end
    end
  end
end
