# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # 메모 또는 필기 → 기록 승격 (W3-T07).
    #
    # ID·created_at·body·tags 유지, mode를 :memo/:note → :record로 변경.
    # title은 새로 부여(또는 노트면 기존 title prefill 후 사용자 편집), category는 자유 텍스트.
    # promoted_from에 옛 source path 기록 → SoT는 마크다운 파일에 보존.
    class PromoteToRecord
      include Dry::Monads[:result]
      include Persistence

      ALLOWED_SOURCE_MODES = %i[memo note].freeze

      def initialize(vault_repo:, index_repo:, clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @clock = clock
      end

      # @param id       [String] 메모 또는 필기의 ULID
      # @param title    [String] 새 기록의 제목 (필수)
      # @param category [String] 카테고리 (자유 텍스트, 필수)
      # @param tags     [Array<String>, nil] override. nil이면 source의 태그 그대로.
      # @return [Dry::Monads::Result] Success(Record) | Failure(Symbol)
      def call(id:, title:, category:, tags: nil)
        return Failure(:empty_title) if blank?(title)
        return Failure(:empty_category) if blank?(category)

        indexed = @index_repo.find(id)
        return Failure(:not_found) if indexed.nil?
        return Failure(:not_promotable) unless ALLOWED_SOURCE_MODES.include?(indexed.mode)

        source =
          begin
            @vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            return Failure(:file_missing)
          end

        record = Domain::Record.new(
          id: source.id,                # ULID 유지 (backlinks 보존)
          body: source.body,            # 본문 유지
          created_at: source.created_at, # 작성 시각 보존
          updated_at: @clock.now,       # 승격 시각
          title: title.strip,
          category: category.strip,
          tags: build_tags(source, tags),
          template: source.template,
          promoted_from: indexed.path
        )

        repersist!(record, old_path: indexed.path)
        Success(record)
      end

      private

      def blank?(value)
        value.to_s.strip.empty?
      end

      def build_tags(source, override)
        return source.tags if override.nil?
        Domain::ValueObjects::TagSet.new(override)
      end
    end
  end
end
