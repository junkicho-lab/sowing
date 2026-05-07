# frozen_string_literal: true

module Sowing
  module Domain
    # 필기 (Note): 외부 자료를 정리·요약하는 학습 행위.
    # 옵시디언 매핑: 20_Notes/{category}/{title}.md
    class Note
      include Entry

      MODE = :note

      attr_reader :id, :body, :tags, :title, :template, :category, :source,
        :created_at, :updated_at

      def initialize(id:, body:, created_at:,
        title: nil, tags: ValueObjects::TagSet.new, template: nil, updated_at: nil,
        category: nil, source: nil)
        validate_ulid!(id, :id)
        validate_string!(body, :body)
        validate_tag_set!(tags)
        validate_time!(created_at, :created_at)
        validate_optional_string!(title, :title)
        validate_optional_string!(template, :template)
        validate_optional_string!(category, :category)
        validate_optional_string!(source, :source)
        updated_at ||= created_at
        validate_time!(updated_at, :updated_at)

        @id = id
        @body = body.freeze
        @tags = tags
        @title = title&.freeze
        @template = template&.freeze
        @category = category&.freeze
        @source = source&.freeze
        @created_at = created_at
        @updated_at = updated_at
        freeze
      end

      def mode
        MODE
      end

      def to_frontmatter
        common_frontmatter.merge(
          "category" => category,
          "source" => source
        ).compact
      end
    end
  end
end
