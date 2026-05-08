# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # 기록 갱신. id·created_at은 불변, updated_at만 갱신.
    # path 변경(title/category) 시 옛 파일은 휴지통으로.
    class UpdateRecord
      include Dry::Monads[:result]
      include Persistence

      def initialize(vault_repo:, index_repo:, clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @clock = clock
      end

      # @return [Dry::Monads::Result] Success(Record) | Failure(Symbol)
      def call(id:, title:, body:, category:, tags: [], template: nil, promoted_from: nil)
        return Failure(:empty_title) if blank?(title)
        return Failure(:empty_body) if blank?(body)
        return Failure(:empty_category) if blank?(category)

        indexed = @index_repo.find(id)
        return Failure(:not_found) if indexed.nil? || indexed.mode != :record

        existing =
          begin
            @vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            return Failure(:file_missing)
          end

        record = Domain::Record.new(
          id: existing.id,
          created_at: existing.created_at,
          updated_at: @clock.now,
          title: title.strip,
          body: body.strip,
          category: category.strip,
          tags: Domain::ValueObjects::TagSet.new(tags),
          template: template,
          promoted_from: promoted_from
        )

        repersist!(record, old_path: indexed.path)
        Success(record)
      end

      private

      def blank?(value)
        value.to_s.strip.empty?
      end
    end
  end
end
