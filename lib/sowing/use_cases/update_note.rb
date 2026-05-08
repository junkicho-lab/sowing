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
      # @param expected_file_hash [String, nil] 폼 로드 시점의 disk hash (낙관적 잠금)
      # @param force [Boolean] true면 hash 검사 스킵 + 외부 수정본을 .sowing/conflicts/로 백업
      # @return [Dry::Monads::Result]
      #   Success(Note) | Failure(Symbol) | Failure([:conflict, payload])
      def call(id:, title:, body:, category:, source:, tags: [], template: nil,
        expected_file_hash: nil, force: false)
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

        # 낙관적 잠금: 폼 로드 시점 hash와 현재 disk hash 다르면 외부 수정 발생.
        # force=true면 사용자가 "Keep Mine" 선택한 상황 — 외부본을 백업한 뒤 덮어쓰기.
        unless force
          current_hash = @vault_repo.file_hash(indexed.path)
          if expected_file_hash && current_hash && expected_file_hash != current_hash
            return Failure([:conflict, conflict_payload(existing, indexed, current_hash,
              title: title, body: body, category: category, source: source, tags: tags)])
          end
        end

        @vault_repo.backup_conflict(indexed.path) if force

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

      def conflict_payload(existing, indexed, current_hash, title:, body:, category:, source:, tags:)
        {
          path: indexed.path,
          their_hash: current_hash,
          their_title: existing.title,
          their_body: existing.body,
          their_category: existing.category,
          their_source: existing.source,
          their_tags: existing.tags.to_a,
          mine_title: title,
          mine_body: body,
          mine_category: category,
          mine_source: source,
          mine_tags: Array(tags)
        }
      end
    end
  end
end
