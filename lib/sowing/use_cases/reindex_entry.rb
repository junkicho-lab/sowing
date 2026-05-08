# frozen_string_literal: true

require "dry/monads"
require "pathname"

module Sowing
  module UseCases
    # 외부 에디터(옵시디언 등)가 볼트의 파일을 변경했을 때 인덱스를 재동기화 (W5-T02).
    #
    # FileWatcher 이벤트를 입력으로 받아 처리:
    #   - :modified, :added → 파일을 다시 읽어 frontmatter로 도메인 복원 + 인덱스 upsert
    #   - :removed          → path로 entry 찾아 인덱스 row 삭제 (휴지통은 SoT가 아니므로)
    #
    # mtime/hash 비교 최적화 — 변경 없으면 :unchanged 반환하고 작업 스킵.
    # 사용자 자체 쓰기(SafeWriter 경유)는 SelfWriteRegistry로 watcher 단계에서 이미 필터링됨.
    class ReindexEntry
      include Dry::Monads[:result]
      include Persistence

      def initialize(vault_repo:, index_repo:)
        @vault_repo = vault_repo
        @index_repo = index_repo
      end

      # @param event [Hash] {type: :modified|:added|:removed, path: Pathname (절대)}
      # @return [Dry::Monads::Result]
      #   Success(:reindexed | :added | :unchanged | :removed | :not_indexed)
      #   Failure(Symbol | [Symbol, String])
      def call(event)
        abs_path = Pathname.new(event.fetch(:path).to_s)
        rel_path = relative_path(abs_path)

        case event.fetch(:type)
        when :added, :modified then handle_upsert(abs_path, rel_path)
        when :removed then handle_remove(rel_path)
        else Failure(:unknown_event_type)
        end
      end

      private

      def relative_path(abs_path)
        abs_path.relative_path_from(@vault_repo.vault_dir).to_s
      end

      def handle_upsert(abs_path, rel_path)
        return Failure(:file_missing) unless abs_path.exist?

        new_mtime = abs_path.mtime.to_i
        new_hash = file_hash(abs_path)
        existing = @index_repo.find_by_path(rel_path)

        if existing && existing.file_mtime == new_mtime && existing.file_hash == new_hash
          return Success(:unchanged)
        end

        entry = @vault_repo.read(abs_path)
        update_index!(entry, abs_path)
        Success(existing ? :reindexed : :added)
      rescue ArgumentError => e
        # frontmatter 누락·잘못된 mode 등 — adoption(W5-T03)에서 처리할 케이스.
        Failure([:invalid_frontmatter, e.message])
      end

      def handle_remove(rel_path)
        existing = @index_repo.find_by_path(rel_path)
        return Success(:not_indexed) unless existing
        @index_repo.delete(existing.id)
        Success(:removed)
      end
    end
  end
end
