# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # 샘플 시드(W7-T03) 일괄 제거 (W7-T06 설정 화면).
    #
    # ULID prefix `01KR1SAMP` 로 식별된 entry 모두를 휴지통(.sowing/trash)으로 이동하고
    # 인덱스에서 삭제. 마크다운 SoT 원칙(CLAUDE.md 5번): 영구 삭제 금지 — VaultRepo#delete가
    # mv only로 보존.
    #
    # 파일이 이미 사라진 경우(외부에서 수동 삭제 등)에도 인덱스는 정리한다.
    class DeleteSamples
      include Dry::Monads[:result]

      def initialize(
        vault_repo: nil,
        index_repo: nil
      )
        @vault_repo = vault_repo || Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        @index_repo = index_repo || Repositories::IndexRepo.new
      end

      # @return [Result] Success(removed_count)
      def call
        rows = @index_repo.find_samples
        removed = 0

        rows.each do |row|
          begin
            @vault_repo.delete(row[:path])
          rescue Errno::ENOENT
            # 외부에서 이미 삭제됨 — 인덱스만 정리하면 됨.
          end
          @index_repo.delete(row[:id])
          removed += 1
        end

        Success(removed)
      end
    end
  end
end
