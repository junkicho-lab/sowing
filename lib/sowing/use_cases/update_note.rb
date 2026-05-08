# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # 필기 갱신. id·created_at은 불변, updated_at만 @clock.now로 갱신.
    # path가 바뀌는 변경(title·category)에도 옛 파일은 휴지통으로 보존 (CLAUDE.md 원칙 5).
    class UpdateNote
      include Dry::Monads[:result]
      include Persistence

      CATEGORIES = CreateNote::CATEGORIES

      def initialize(vault_repo:, index_repo:, clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @clock = clock
      end

      # @param id [String, Sowing::Domain::ValueObjects::Ulid]
      # @return [Dry::Monads::Result] Success(Note) | Failure(Symbol)
      def call(id:, title:, body:, category:, source:, tags: [], template: nil)
        return Failure(:empty_title) if blank?(title)
        return Failure(:empty_body) if blank?(body)
        return Failure(:empty_category) if blank?(category)
        return Failure(:invalid_category) unless CATEGORIES.include?(category)
        return Failure(:empty_source) if blank?(source)

        indexed = @index_repo.find(id)
        return Failure(:not_found) if indexed.nil? || indexed.mode != :note

        existing =
          begin
            @vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            return Failure(:file_missing)
          end

        note = Domain::Note.new(
          id: existing.id,                  # 불변 (ULID 영구 식별자)
          created_at: existing.created_at,  # 불변 (생성 시각 보존)
          updated_at: @clock.now,           # 갱신
          title: title.strip,
          body: body.strip,
          category: category,
          source: source.strip,
          tags: Domain::ValueObjects::TagSet.new(tags),
          template: template
        )

        repersist!(note, old_path: indexed.path)
        Success(note)
      end

      private

      def blank?(value)
        value.to_s.strip.empty?
      end
    end
  end
end
