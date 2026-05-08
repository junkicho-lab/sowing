# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # 메모 → 필기 승격 (W3-T06).
    #
    # ID·created_at·body는 그대로 유지하면서 mode를 :memo → :note로 변경하고
    # title·category·source를 새로 부여. 옛 path(`00_Inbox/...`)는 휴지통으로 이동
    # (CLAUDE.md 원칙 5: 영구 삭제 금지). VaultRepo.update가 path 이동을 트랜잭션으로 처리.
    #
    # ID 유지 → links 그래프의 backlinks 자동 보존.
    class PromoteToNote
      include Dry::Monads[:result]
      include Persistence

      CATEGORIES = CreateNote::CATEGORIES

      def initialize(vault_repo:, index_repo:, clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @clock = clock
      end

      # @param id       [String] 메모의 ULID
      # @param title    [String] 새 필기의 제목
      # @param category [String] 카테고리 (CATEGORIES 중 하나)
      # @param source   [String] 출처
      # @param tags     [Array<String>, nil] override. nil이면 메모의 태그를 그대로.
      # @return [Dry::Monads::Result] Success(Note) | Failure(Symbol)
      def call(id:, title:, category:, source:, tags: nil)
        return Failure(:empty_title) if blank?(title)
        return Failure(:empty_category) if blank?(category)
        return Failure(:invalid_category) unless CATEGORIES.include?(category)
        return Failure(:empty_source) if blank?(source)

        indexed = @index_repo.find(id)
        return Failure(:not_found) if indexed.nil?
        return Failure(:not_a_memo) if indexed.mode != :memo

        memo =
          begin
            @vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            return Failure(:file_missing)
          end

        note = Domain::Note.new(
          id: memo.id,                  # ULID 유지 (backlinks 보존)
          body: memo.body,              # 본문 유지
          created_at: memo.created_at,  # 작성 시각 보존
          updated_at: @clock.now,       # 승격 시각
          title: title.strip,
          category: category,
          source: source.strip,
          tags: build_tags(memo, tags),
          template: memo.template,
          promoted_from: indexed.path   # 옛 메모 vault-기준 상대 경로 기록
        )

        repersist!(note, old_path: indexed.path)
        Success(note)
      end

      private

      def blank?(value)
        value.to_s.strip.empty?
      end

      def build_tags(memo, override)
        return memo.tags if override.nil?
        Domain::ValueObjects::TagSet.new(override)
      end
    end
  end
end
