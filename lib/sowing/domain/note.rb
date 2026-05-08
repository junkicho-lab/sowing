# frozen_string_literal: true

module Sowing
  module Domain
    # 필기 (Note): 외부 자료를 정리·요약하는 학습 행위.
    # 옵시디언 매핑: 20_Notes/{category}/{title}.md
    #
    # promoted_from은 메모/다른 노트로부터 승격되었을 때 원본 vault 상대 경로.
    # CreateNote는 nil로 두고, PromoteToNote가 채움 (W3-T06).
    class Note
      include Entry

      MODE = :note

      attr_reader :id, :body, :tags, :title, :template, :category, :source, :promoted_from,
        :created_at, :updated_at

      def initialize(id:, body:, created_at:,
        title: nil, tags: ValueObjects::TagSet.new, template: nil, updated_at: nil,
        category: nil, source: nil, promoted_from: nil)
        validate_ulid!(id, :id)
        validate_string!(body, :body)
        validate_tag_set!(tags)
        validate_time!(created_at, :created_at)
        validate_optional_string!(title, :title)
        validate_optional_string!(template, :template)
        validate_optional_string!(category, :category)
        validate_optional_string!(source, :source)
        validate_optional_string!(promoted_from, :promoted_from)
        updated_at ||= created_at
        validate_time!(updated_at, :updated_at)

        @id = id
        @body = body.freeze
        @tags = tags
        @title = title&.freeze
        @template = template&.freeze
        @category = category&.freeze
        @source = source&.freeze
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
          "source" => source,
          "promoted_from" => promoted_from
        ).compact
      end
    end
  end
end
