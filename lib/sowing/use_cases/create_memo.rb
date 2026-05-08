# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # 메모 생성 Use Case.
    # 흐름: body 검증 → 도메인 Memo 생성 → VaultRepo write + IndexRepo upsert (Persistence)
    # 도메인은 type-only 검증만 하므로, 빈 본문 등 비즈니스 규칙은 본 Use Case가 거부.
    class CreateMemo
      include Dry::Monads[:result]
      include Persistence

      def initialize(vault_repo:, index_repo:, clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @clock = clock
      end

      # @param body [String]   메모 본문
      # @param tags [Array<String>] 태그 목록 (기본 빈 배열)
      # @return [Dry::Monads::Result] Success(Memo) | Failure(Symbol)
      def call(body:, tags: [])
        return Failure(:empty_body) if body.to_s.strip.empty?

        memo = Domain::Memo.new(
          id: Domain::ValueObjects::Ulid.generate,
          body: body.strip,
          tags: Domain::ValueObjects::TagSet.new(tags),
          created_at: @clock.now
        )

        persist!(memo)
        Success(memo)
      end
    end
  end
end
