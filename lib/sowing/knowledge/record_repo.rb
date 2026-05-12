# frozen_string_literal: true

module Sowing
  module Knowledge
    # Knowledge::RecordRepo — Record 영속화 어댑터 (Phase R Stage 3 R3-T03).
    #
    # 책임:
    #   - Knowledge::Record 의 파일 저장 (30_Records/{YYYY}/{category}/) + SQLite 인덱싱
    #   - id / 최근순 조회 시 frontmatter 재파싱으로 source·subject 복원
    #
    # 설계:
    #   - VaultRepo / IndexRepo 를 직접 사용 (Capture::ItemRepo 와 동일 패턴)
    #   - VaultRepo.write 는 entry.mode==:record + entry.category 필수 — Knowledge::Record
    #     가 category 보유 시 그대로 작동, 미보유 시 ArgumentError (VaultRepo 에서)
    #   - 옛 Domain::Record/Note 와 무관 — Knowledge::Record 는 superset 으로 독립
    #
    # 의존: Core (Parser·Filesystem), Capture::Item (subject Symbol 검증 무관 — fm 만 다룸)
    class RecordRepo
      def initialize(vault_repo: nil, index_repo: nil, parser: nil)
        @vault_repo = vault_repo || Repositories::VaultRepo.new(vault_dir: Core::Paths.vault_dir)
        @index_repo = index_repo || Repositories::IndexRepo.new
        @parser = parser || Core::Markdown::Parser.new
      end

      # Record 를 파일로 저장 + 인덱스 upsert.
      # @param record [Sowing::Knowledge::Record]
      # @return [Sowing::Knowledge::Record] 그대로 반환 (불변)
      def create(record)
        unless record.is_a?(Record)
          raise ArgumentError, "record 는 Sowing::Knowledge::Record 이어야 합니다 (받은 타입: #{record.class})"
        end

        abs_path = @vault_repo.write(record)
        rel_path = abs_path.relative_path_from(@vault_repo.vault_dir).to_s

        @index_repo.upsert(
          record,
          path: rel_path,
          file_mtime: abs_path.mtime.to_i,
          file_hash: @vault_repo.file_hash(abs_path),
          word_count: word_count(record.body)
        )

        record
      end

      # ULID 로 Record 조회. mode :record 가 아닌 entry 는 nil.
      # 옛 :note mode 는 Stage 5 마이그레이션 전까지 본 repo 가 다루지 않음 (BC 격리).
      # @return [Sowing::Knowledge::Record, nil]
      def find(id)
        indexed = @index_repo.find(id)
        return nil unless indexed
        return nil unless indexed.mode == :record
        read_record(indexed.path)
      end

      # 최근 생성된 Record 들 (created_at desc).
      # @return [Array<Sowing::Knowledge::Record>]
      def recent(limit: 10)
        @index_repo.list(mode: :record, limit: limit).map { |e| read_record(e.path) }
      end

      private

      def read_record(rel_path)
        abs = @vault_repo.vault_dir.join(rel_path)
        parsed = @parser.parse(abs.read(encoding: "UTF-8"))
        fm = parsed.frontmatter

        Record.new(
          id: Domain::ValueObjects::Ulid.parse(fm.fetch("id")),
          body: parsed.body.chomp,
          created_at: Time.iso8601(fm.fetch("created_at")),
          updated_at: Time.iso8601(fm.fetch("updated_at")),
          title: fm["title"],
          tags: Domain::ValueObjects::TagSet.new(fm["tags"] || []),
          template: fm["template"],
          category: fm["category"],
          source: fm["source"],
          promoted_from: fm["promoted_from"],
          subject: fm["subject"]&.to_sym
        )
      end

      def word_count(body)
        body.to_s.split(/\s+/).reject(&:empty?).size
      end
    end
  end
end
