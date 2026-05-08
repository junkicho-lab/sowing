# frozen_string_literal: true

require "digest"
require "dry/monads"

module Sowing
  module UseCases
    # 메모 생성 Use Case.
    # 흐름: body 검증 → 도메인 Memo 생성 → 마크다운 파일 저장(VaultRepo) → 인덱스 갱신(IndexRepo)
    #
    # 도메인은 type-only 검증만 하므로, 빈 본문 등 비즈니스 규칙은 본 Use Case가 거부.
    class CreateMemo
      include Dry::Monads[:result]

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

        absolute_path = @vault_repo.write(memo)
        relative_path = absolute_path.relative_path_from(@vault_repo.vault_dir)

        @index_repo.upsert(
          memo,
          path: relative_path.to_s,
          file_mtime: absolute_path.mtime.to_i,
          file_hash: file_hash(absolute_path),
          word_count: memo.body.split.size
        )

        Success(memo)
      end

      private

      # SHA-256 hex의 앞 16자 (SPEC §8.3 file_hash 정의).
      def file_hash(path)
        Digest::SHA256.hexdigest(path.binread)[0, 16]
      end
    end
  end
end
