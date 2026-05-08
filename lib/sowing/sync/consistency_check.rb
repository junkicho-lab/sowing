# frozen_string_literal: true

require "pathname"

module Sowing
  module Sync
    # 부팅 시 볼트 ↔ 인덱스 일관성 검증 + 자동 동기화 (W5-T04).
    #
    # 발견되는 4가지 케이스:
    #   1. 디스크·인덱스 모두 존재, mtime/hash 일치 → :unchanged (스킵)
    #   2. 디스크·인덱스 모두 존재, 다름            → :reindexed (재인덱싱)
    #   3. 디스크에만 존재 (인덱스 누락)            → :added (입양 또는 신규 인덱싱)
    #   4. 인덱스에만 존재 (파일 사라짐)            → :removed (인덱스 row 삭제)
    #
    # Coordinator#handle_event를 재사용 — ReindexEntry + AdoptOrphan 폴백을 그대로 활용한다.
    # 인덱스를 통째로 날리고 부팅해도 자동 재구축 (ROADMAP W5-T04 검증 시나리오).
    class ConsistencyCheck
      # vault 내부 메타 디렉토리 — 트래시 등은 인덱스 대상 아님.
      IGNORED_DIR_RE = %r{(^|/)\.sowing(/|$)}

      Summary = Struct.new(:unchanged, :reindexed, :added, :adopted, :removed, :not_indexed, :errors, keyword_init: true) do
        def total
          unchanged + reindexed + added + adopted + removed + not_indexed + errors.size
        end

        def to_h
          {
            unchanged: unchanged, reindexed: reindexed, added: added,
            adopted: adopted, removed: removed, not_indexed: not_indexed,
            errors: errors
          }
        end
      end

      def initialize(vault_dir:, index_repo:, coordinator:)
        @vault_dir = Pathname.new(vault_dir.to_s).expand_path
        @index_repo = index_repo
        @coordinator = coordinator
      end

      # @return [Summary]
      def run
        summary = Summary.new(unchanged: 0, reindexed: 0, added: 0, adopted: 0,
          removed: 0, not_indexed: 0, errors: [])

        disk_rels = scan_disk
        indexed_rels = @index_repo.all_paths.to_set

        # 디스크에 있는 파일은 :modified로 시도 (handle_event가 mtime/hash 비교로 unchanged 단축).
        disk_rels.each do |rel|
          tally(summary, @coordinator.handle_event(type: :modified, path: @vault_dir.join(rel)))
        end

        # 인덱스에만 있는 path → :removed.
        (indexed_rels - disk_rels).each do |rel|
          tally(summary, @coordinator.handle_event(type: :removed, path: @vault_dir.join(rel)))
        end

        summary
      end

      private

      def scan_disk
        return Set.new unless @vault_dir.exist?
        Dir.glob(@vault_dir.join("**/*.md"))
          .reject { |p| p.match?(IGNORED_DIR_RE) }
          .map { |p| Pathname.new(p).relative_path_from(@vault_dir).to_s }
          .to_set
      end

      def tally(summary, result)
        if result.success?
          case result.value!
          when :unchanged then summary.unchanged += 1
          when :reindexed then summary.reindexed += 1
          when :added then summary.added += 1
          when :adopted then summary.adopted += 1
          when :removed then summary.removed += 1
          when :not_indexed then summary.not_indexed += 1
          end
        else
          summary.errors << result.failure
        end
      end
    end
  end
end
