# frozen_string_literal: true

require "fileutils"
require "pathname"
require "time"

module Sowing
  module Repositories
    # 옵시디언 호환 마크다운 볼트(폴더)에 대한 영속화 어댑터.
    #
    # 책임:
    #   - 도메인(Memo/Note/Record) ↔ 마크다운 파일 변환 + 저장 위치 결정
    #   - 단방향 의존(Domain → Repository → Infrastructure)을 지키며 SafeWriter·Parser·Serializer를 조립
    #   - 영구 삭제 금지: delete는 .sowing/trash/ 로 이동만 (CLAUDE.md 원칙 5)
    #
    # 경로 규칙 (SPEC §8.2):
    #   - Memo:   00_Inbox/YYYY-MM-DD_HHmmss.md
    #   - Note:   20_Notes/{category}/{title|timestamp}.md   (category 필수)
    #   - Record: 30_Records/{YYYY}/{category}/{title|timestamp}.md (category 필수)
    #
    # 파일명 충돌:
    #   - foo.md → foo-2.md → foo-3.md … (최대 999)
    class VaultRepo
      ILLEGAL_FILENAME_CHARS = %r{[\\/<>:"|?*\x00-\x1F]}
      MAX_COLLISION_RETRIES = 999

      attr_reader :vault_dir

      def initialize(vault_dir:,
        safe_writer: Infrastructure::Filesystem::SafeWriter.new,
        parser: Infrastructure::Markdown::Parser.new,
        serializer: Infrastructure::Markdown::Serializer.new)
        @vault_dir = Pathname.new(vault_dir.to_s).expand_path
        @safe_writer = safe_writer
        @parser = parser
        @serializer = serializer
      end

      # 도메인 객체를 마크다운 파일로 저장. 충돌 시 카운터 suffix.
      # @param entry [Sowing::Domain::Memo, Note, Record]
      # @return [Pathname] 실제 저장된 절대 경로 (NFC 정규화 적용)
      def write(entry)
        target = avoid_collision(resolve_path(entry))
        @safe_writer.atomic_write(target, @serializer.serialize(entry))
      end

      # 기존 entry를 갱신. path가 바뀌면(예: title·category 변경) 옛 파일은 휴지통으로,
      # 새 path에 새 파일을 쓴다. path가 같으면 SafeWriter의 원자적 교체로 덮어쓰기.
      #
      # @param entry [Sowing::Domain::*]
      # @param old_path [String, Pathname] 기존 파일의 vault-기준 상대 경로 또는 절대 경로
      # @return [Pathname] 실제 저장된 절대 경로
      def update(entry, old_path:)
        new_target = resolve_path(entry)
        old_abs = absolute(old_path)

        if old_abs == new_target
          @safe_writer.atomic_write(new_target, @serializer.serialize(entry))
        else
          new_target = avoid_collision(new_target)
          written = @safe_writer.atomic_write(new_target, @serializer.serialize(entry))
          delete(old_abs) if old_abs.exist?
          written
        end
      end

      # 마크다운 파일에서 도메인 객체 복원.
      # @param path [String, Pathname] 절대 경로 또는 vault 기준 상대 경로
      # @return [Sowing::Domain::Memo, Note, Record]
      # @raise [ArgumentError] frontmatter 필수 필드 결손, 잘못된 mode 등
      def read(path)
        abs = absolute(path)
        parsed = @parser.parse(abs.read)
        reconstruct(parsed.frontmatter, parsed.body)
      end

      # 특정 모드의 모든 마크다운 파일 경로.
      # @param mode [Symbol] :memo, :note, :record
      # @return [Array<Pathname>] 절대 경로 배열 (정렬됨)
      def list(mode:)
        dir = directory_for(mode)
        return [] unless dir.exist?
        Dir.glob(dir.join("**/*.md")).sort.map { |p| Pathname.new(p) }
      end

      # 파일을 휴지통으로 이동. 영구 삭제 금지 (CLAUDE.md 원칙 5).
      # 휴지통 구조: .sowing/trash/{원본 vault 기준 상대 경로}
      # @param path [String, Pathname]
      # @return [Pathname] 휴지통 내 실제 위치 (충돌 시 카운터 suffix 적용)
      # @raise [Errno::ENOENT] 원본 파일이 없을 때
      def delete(path)
        abs = absolute(path)
        raise Errno::ENOENT, abs.to_s unless abs.exist?

        rel = abs.relative_path_from(@vault_dir)
        target = @vault_dir.join(".sowing/trash", rel)
        FileUtils.mkdir_p(target.dirname)
        target = avoid_collision(target)
        FileUtils.mv(abs.to_s, target.to_s)
        target
      end

      private

      def resolve_path(entry)
        case entry.mode
        when :memo
          @vault_dir.join("00_Inbox", "#{timestamp(entry.created_at)}.md")
        when :note
          require_category!(entry, :note)
          @vault_dir.join("20_Notes", entry.category, "#{filename_for(entry)}.md")
        when :record
          require_category!(entry, :record)
          year = entry.created_at.strftime("%Y")
          @vault_dir.join("30_Records", year, entry.category, "#{filename_for(entry)}.md")
        else
          raise ArgumentError, "지원하지 않는 mode: #{entry.mode.inspect}"
        end
      end

      def filename_for(entry)
        if entry.title && !entry.title.strip.empty?
          slug(entry.title)
        else
          timestamp(entry.created_at)
        end
      end

      def slug(text)
        cleaned = text.gsub(ILLEGAL_FILENAME_CHARS, "-").strip
        cleaned.empty? ? "untitled" : cleaned
      end

      def timestamp(time)
        time.strftime("%Y-%m-%d_%H%M%S")
      end

      def require_category!(entry, mode_label)
        return if entry.category && !entry.category.strip.empty?
        raise ArgumentError, "#{mode_label}는 category가 필수입니다 (디렉토리 구조 강제)"
      end

      def avoid_collision(path)
        return path unless path.exist?

        base = path.basename(".md").to_s
        dir = path.dirname
        (2..MAX_COLLISION_RETRIES).each do |counter|
          candidate = dir.join("#{base}-#{counter}.md")
          return candidate unless candidate.exist?
        end
        raise "파일명 충돌 회피 실패 (#{path}, counter > #{MAX_COLLISION_RETRIES})"
      end

      def absolute(path)
        pathname = Pathname.new(path.to_s)
        pathname.absolute? ? pathname : @vault_dir.join(pathname)
      end

      def directory_for(mode)
        case mode
        when :memo then @vault_dir.join("00_Inbox")
        when :note then @vault_dir.join("20_Notes")
        when :record then @vault_dir.join("30_Records")
        else raise ArgumentError, "지원하지 않는 mode: #{mode.inspect}"
        end
      end

      def reconstruct(frontmatter, body)
        mode = frontmatter["mode"]&.to_sym
        common = common_attrs(frontmatter, body)

        case mode
        when :memo
          Domain::Memo.new(**common)
        when :note
          Domain::Note.new(**common.merge(
            category: frontmatter["category"],
            source: frontmatter["source"]
          ))
        when :record
          Domain::Record.new(**common.merge(
            category: frontmatter["category"],
            promoted_from: frontmatter["promoted_from"]
          ))
        else
          raise ArgumentError, "지원하지 않는 mode: #{mode.inspect}"
        end
      end

      def common_attrs(frontmatter, body)
        {
          id: Domain::ValueObjects::Ulid.parse(fetch_required(frontmatter, "id")),
          body: body.chomp,
          created_at: Time.iso8601(fetch_required(frontmatter, "created_at")),
          updated_at: Time.iso8601(fetch_required(frontmatter, "updated_at")),
          title: frontmatter["title"],
          tags: Domain::ValueObjects::TagSet.new(frontmatter["tags"] || []),
          template: frontmatter["template"]
        }
      end

      def fetch_required(hash, key)
        value = hash[key]
        raise ArgumentError, "frontmatter에 필수 키 '#{key}'가 없습니다" if value.nil?
        value
      end
    end
  end
end
