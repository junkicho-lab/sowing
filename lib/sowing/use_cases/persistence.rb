# frozen_string_literal: true

require "digest"

module Sowing
  module UseCases
    # 도메인 Entry를 마크다운 파일과 SQLite 인덱스에 동시 영속화.
    # CreateMemo, CreateNote, CreateRecord 등에서 include하여 재사용.
    #
    # 포함 클래스의 #initialize는 `@vault_repo`, `@index_repo`를 세팅해야 한다.
    module Persistence
      private

      # 신규 영속화. 새 path에 마크다운 작성 + 인덱스 row 신규/멱등 갱신.
      # @param entry [Sowing::Domain::*]
      # @return [Pathname] 절대 경로 (NFC 정규화 적용)
      def persist!(entry)
        absolute_path = @vault_repo.write(entry)
        update_index!(entry, absolute_path)
        absolute_path
      end

      # 기존 entry 갱신. path가 바뀌면 옛 파일을 휴지통으로, 인덱스 path 컬럼도 갱신.
      # @param entry [Sowing::Domain::*]
      # @param old_path [String, Pathname] 기존 파일의 vault-기준 상대 또는 절대 경로
      # @return [Pathname] 새 절대 경로
      def repersist!(entry, old_path:)
        absolute_path = @vault_repo.update(entry, old_path: old_path)
        update_index!(entry, absolute_path)
        absolute_path
      end

      def update_index!(entry, absolute_path)
        relative_path = absolute_path.relative_path_from(@vault_repo.vault_dir)
        @index_repo.upsert(
          entry,
          path: relative_path.to_s,
          file_mtime: absolute_path.mtime.to_i,
          file_hash: file_hash(absolute_path),
          word_count: entry.body.split.size
        )
      end

      # SHA-256 hex의 앞 16자 (SPEC §8.3 file_hash 정의).
      def file_hash(path)
        Digest::SHA256.hexdigest(path.binread)[0, 16]
      end
    end
  end
end
