# frozen_string_literal: true

require "dry/monads"
require "pathname"

module Sowing
  module UseCases
    # 외부 에디터(옵시디언 등)가 frontmatter 없이 만든 .md 파일을 자동 입양 (W5-T03).
    #
    # 흐름:
    #   1. 경로로 mode 추론 (00_Inbox/ → memo, 20_Notes/{cat}/ → note, 30_Records/{Y}/{cat}/ → record)
    #   2. 본문 첫 H1을 제목으로 (없으면 파일명)
    #   3. ULID 생성 + frontmatter 부착 → SafeWriter로 in-place 기록 (사용자가 만든 위치 보존)
    #   4. 인덱스 upsert
    #
    # 같은 위치(orphan path)에 그대로 둬서 옵시디언/사용자 의도를 존중. VaultRepo.write의
    # path 재계산을 우회하므로 SafeWriter를 직접 사용한다 (write_in_place 패턴).
    class AdoptOrphan
      include Dry::Monads[:result]
      include Persistence

      H1_RE = /\A\s*#\s+(.+?)\s*$/

      def initialize(vault_repo:,
        index_repo:,
        safe_writer: Infrastructure::Filesystem::SafeWriter.new,
        clock: Time)
        @vault_repo = vault_repo
        @index_repo = index_repo
        @safe_writer = safe_writer
        @clock = clock
      end

      # @param event [Hash] {type: :added | :modified, path: Pathname (절대)}
      # @return [Result] Success(Domain::Memo|Note|Record) | Failure
      def call(event)
        abs_path = Pathname.new(event.fetch(:path).to_s)
        return Failure(:file_missing) unless abs_path.exist?

        rel_path = abs_path.relative_path_from(@vault_repo.vault_dir)
        mode = detect_mode(rel_path)
        return Failure(:unsupported_path) unless mode

        raw = abs_path.read
        return Failure(:not_orphan) if has_frontmatter?(raw)

        title, body = extract_title_and_body(raw, abs_path)
        entry = build_entry(mode: mode, rel_path: rel_path, title: title, body: body, file_mtime: abs_path.mtime)

        @safe_writer.atomic_write(abs_path, entry.to_markdown)
        update_index!(entry, abs_path)

        Success(entry)
      end

      private

      def has_frontmatter?(content)
        content.start_with?("---\n", "---\r\n")
      end

      def detect_mode(rel_path)
        parts = rel_path.to_s.split("/")
        case parts.first
        when "00_Inbox" then :memo
        when "20_Notes" then (parts.size >= 3) ? :note : nil
        when "30_Records" then (parts.size >= 4) ? :record : nil
        end
      end

      def extract_title_and_body(content, abs_path)
        first_line, rest = content.split("\n", 2)
        if (m = first_line&.match(H1_RE))
          [m[1], (rest || "").sub(/\A\n+/, "")]
        else
          [abs_path.basename(".md").to_s, content]
        end
      end

      def build_entry(mode:, rel_path:, title:, body:, file_mtime:)
        common = {
          id: Domain::ValueObjects::Ulid.generate,
          body: body.chomp,
          tags: Domain::ValueObjects::TagSet.new([]),
          created_at: file_mtime,
          updated_at: @clock.now,
          title: title
        }

        case mode
        when :memo
          Domain::Memo.new(**common)
        when :note
          Domain::Note.new(**common.merge(category: rel_path.to_s.split("/")[1], source: "외부"))
        when :record
          Domain::Record.new(**common.merge(category: rel_path.to_s.split("/")[2]))
        end
      end
    end
  end
end
