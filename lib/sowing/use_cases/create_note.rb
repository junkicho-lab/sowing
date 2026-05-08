# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # 필기 생성 Use Case.
    # 메모와 달리 title·category·source가 비즈니스적으로 필수 (디렉토리 구조·옵시디언 분류 규칙).
    # 카테고리는 SPEC §8.2 디렉토리 enum: lessons / trainings / books / meetings.
    class CreateNote
      include Dry::Monads[:result]
      include Persistence

      CATEGORIES = %w[lessons trainings books meetings].freeze

      def initialize(vault_repo:, index_repo:, clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @clock = clock
      end

      # @return [Dry::Monads::Result] Success(Note) | Failure(Symbol)
      def call(title:, body:, category:, source:, tags: [], template: nil)
        return Failure(:empty_title) if blank?(title)
        return Failure(:empty_body) if blank?(body)
        return Failure(:empty_category) if blank?(category)
        return Failure(:invalid_category) unless CATEGORIES.include?(category)
        return Failure(:empty_source) if blank?(source)

        note = Domain::Note.new(
          id: Domain::ValueObjects::Ulid.generate,
          title: title.strip,
          body: body.strip,
          category: category,
          source: source.strip,
          tags: Domain::ValueObjects::TagSet.new(tags),
          template: template,
          created_at: @clock.now
        )

        persist!(note)
        Success(note)
      end

      private

      def blank?(value)
        value.to_s.strip.empty?
      end
    end
  end
end
