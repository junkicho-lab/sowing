# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # 기록 생성 — 자기 경험·통찰의 영구 보관용 깊이 있는 글.
    # Note와 달리 category는 자유 텍스트 (사용자가 직접 의미 부여).
    # promoted_from은 메모/필기 승격 시 원본 경로 (선택).
    class CreateRecord
      include Dry::Monads[:result]
      include Persistence

      def initialize(vault_repo:, index_repo:, clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @clock = clock
      end

      # @return [Dry::Monads::Result] Success(Record) | Failure(Symbol)
      def call(title:, body:, category:, tags: [], template: nil, promoted_from: nil)
        return Failure(:empty_title) if blank?(title)
        return Failure(:empty_body) if blank?(body)
        return Failure(:empty_category) if blank?(category)

        record = Domain::Record.new(
          id: Domain::ValueObjects::Ulid.generate,
          title: title.strip,
          body: body.strip,
          category: category.strip,
          tags: Domain::ValueObjects::TagSet.new(tags),
          template: template,
          promoted_from: promoted_from,
          created_at: @clock.now
        )

        persist!(record)
        Success(record)
      end

      private

      def blank?(value)
        value.to_s.strip.empty?
      end
    end
  end
end
