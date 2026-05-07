# frozen_string_literal: true

module Sowing
  module Domain
    # 기록 (Record): 자기 경험·통찰의 영구 보관용 깊이 있는 글.
    # 옵시디언 매핑: 30_Records/{year}/{category}/{title}.md
    class Record
      include Entry

      MODE = :record

      attr_reader :id, :body, :tags, :title, :template, :category, :promoted_from,
        :created_at, :updated_at

      def initialize(id:, body:, created_at:,
        title: nil, tags: ValueObjects::TagSet.new, template: nil, updated_at: nil,
        category: nil, promoted_from: nil)
        validate_ulid!(id, :id)
        validate_string!(body, :body)
        validate_tag_set!(tags)
        validate_time!(created_at, :created_at)
        validate_optional_string!(title, :title)
        validate_optional_string!(template, :template)
        validate_optional_string!(category, :category)
        validate_optional_string!(promoted_from, :promoted_from)
        updated_at ||= created_at
        validate_time!(updated_at, :updated_at)

        @id = id
        @body = body.freeze
        @tags = tags
        @title = title&.freeze
        @template = template&.freeze
        @category = category&.freeze
        @promoted_from = promoted_from&.freeze
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
          "promoted_from" => promoted_from
        ).compact
      end
    end
  end
end
