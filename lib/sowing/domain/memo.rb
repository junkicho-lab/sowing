# frozen_string_literal: true

module Sowing
  module Domain
    # 메모 (Memo): 휘발성 즉시 포착.
    # 옵시디언 매핑: 00_Inbox/{timestamp}.md
    class Memo
      include Entry

      MODE = :memo

      attr_reader :id, :body, :tags, :title, :template, :created_at, :updated_at

      def initialize(id:, body:, created_at:,
        title: nil, tags: ValueObjects::TagSet.new,
        template: nil, updated_at: nil)
        validate_ulid!(id, :id)
        validate_string!(body, :body)
        validate_tag_set!(tags)
        validate_time!(created_at, :created_at)
        validate_optional_string!(title, :title)
        validate_optional_string!(template, :template)
        updated_at ||= created_at
        validate_time!(updated_at, :updated_at)

        @id = id
        @body = body.freeze
        @tags = tags
        @title = title&.freeze
        @template = template&.freeze
        @created_at = created_at
        @updated_at = updated_at
        freeze
      end

      def mode
        MODE
      end

      def to_frontmatter
        common_frontmatter.compact
      end
    end
  end
end
