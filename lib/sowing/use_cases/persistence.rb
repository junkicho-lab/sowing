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

      # @param entry [Sowing::Domain::*]
      # @return [Pathname] 실제 쓰여진 절대 경로 (NFC 정규화 적용)
      def persist!(entry)
        absolute_path = @vault_repo.write(entry)
        relative_path = absolute_path.relative_path_from(@vault_repo.vault_dir)

        @index_repo.upsert(
          entry,
          path: relative_path.to_s,
          file_mtime: absolute_path.mtime.to_i,
          file_hash: file_hash(absolute_path),
          word_count: entry.body.split.size
        )

        absolute_path
      end

      # SHA-256 hex의 앞 16자 (SPEC §8.3 file_hash 정의).
      def file_hash(path)
        Digest::SHA256.hexdigest(path.binread)[0, 16]
      end
    end
  end
end
