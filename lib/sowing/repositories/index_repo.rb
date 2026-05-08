# frozen_string_literal: true

require "time"

module Sowing
  module Repositories
    # SQLite 기반 메타데이터 인덱스 (entries + tags + entry_tags 테이블).
    # 콘텐츠는 절대 저장하지 않음 (CLAUDE.md 원칙 1: SoT는 마크다운).
    #
    # 책임:
    #   - 도메인 Entry + 파일 메타(path, file_mtime, file_hash, word_count) 인덱싱
    #   - 모드/태그/날짜 기반 빠른 검색
    #   - 태그는 정규화 테이블로 분리 + COLLATE NOCASE
    #   - upsert는 트랜잭션 (entry + tag 매핑 원자적)
    class IndexRepo
      ENTRY_COLUMNS = [
        :id, :path, :mode, :title, :category, :template, :source, :promoted_from,
        :created_at, :updated_at, :file_mtime, :file_hash, :word_count, :indexed_at
      ].freeze

      def initialize(db: Infrastructure::DB.connection, clock: Time)
        @db = db
        @clock = clock
      end

      # 도메인 Entry + 파일 메타로 인덱스 갱신 (멱등).
      # 같은 id가 있으면 모든 컬럼을 덮어쓰고, 태그 매핑도 새로 갱신.
      # @return [IndexedEntry]
      def upsert(entry, path:, file_mtime:, file_hash:, word_count: 0)
        row = build_row(entry, path: path, file_mtime: file_mtime, file_hash: file_hash, word_count: word_count)

        @db.transaction do
          @db[:entries].insert_conflict(target: :id, update: row).insert(row)
          sync_tags(entry.id.to_s, entry.tags.to_a)
        end

        find(entry.id)
      end

      # @param id [Sowing::Domain::ValueObjects::Ulid, String]
      # @return [IndexedEntry, nil]
      def find(id)
        row = @db[:entries].where(id: id.to_s).first
        return nil unless row
        to_indexed_entry(row)
      end

      # @param mode [Symbol] :memo, :note, :record
      # @param limit  [Integer, nil] 가져올 최대 행 수
      # @param offset [Integer, nil] 건너뛸 행 수
      # @return [Array<IndexedEntry>] created_at 내림차순
      def list(mode:, limit: nil, offset: nil)
        validate_mode!(mode)
        # 같은 초에 다수 entry가 생성되면 created_at만으로는 ordering이 불안정.
        # ULID id는 lexicographically time-monotonic이므로 보조 정렬로 안정성 확보.
        ds = @db[:entries].where(mode: mode.to_s).order(Sequel.desc(:created_at), Sequel.desc(:id))
        ds = ds.limit(limit) if limit
        ds = ds.offset(offset) if offset
        ds.map { |row| to_indexed_entry(row) }
      end

      # @param mode [Symbol]
      # @return [Integer] 해당 모드 row 수
      def count(mode:)
        validate_mode!(mode)
        @db[:entries].where(mode: mode.to_s).count
      end

      # @param id [Sowing::Domain::ValueObjects::Ulid, String]
      # @return [Boolean] 삭제 여부
      def delete(id)
        @db[:entries].where(id: id.to_s).delete > 0
      end

      # 태그 이름으로 검색 (case-insensitive, COLLATE NOCASE).
      # TagSet 정책에 따라 입력은 strip+downcase로 정규화 후 매칭.
      # @param name [String]
      # @return [Array<IndexedEntry>] created_at 내림차순
      def search_by_tag(name)
        unless name.is_a?(String)
          raise ArgumentError, "tag name은 String이어야 합니다 (받은 타입: #{name.class})"
        end

        normalized = name.strip.downcase
        @db[:entries]
          .join(:entry_tags, entry_id: :id)
          .join(:tags, id: Sequel[:entry_tags][:tag_id])
          .where(Sequel[:tags][:name] => normalized)
          .select_all(:entries)
          .order(Sequel.desc(:created_at))
          .map { |row| to_indexed_entry(row) }
      end

      # @param from [Time]
      # @param to   [Time]
      # @return [Array<IndexedEntry>] 양 끝 inclusive, created_at 내림차순
      def search_by_date(from:, to:)
        unless from.is_a?(Time) && to.is_a?(Time)
          raise ArgumentError, "from·to는 Time이어야 합니다"
        end

        @db[:entries]
          .where(created_at: from.iso8601..to.iso8601)
          .order(Sequel.desc(:created_at))
          .map { |row| to_indexed_entry(row) }
      end

      private

      def build_row(entry, path:, file_mtime:, file_hash:, word_count:)
        {
          id: entry.id.to_s,
          path: path.to_s,
          mode: entry.mode.to_s,
          title: entry.title,
          category: maybe_attr(entry, :category),
          template: entry.template,
          source: maybe_attr(entry, :source),
          promoted_from: maybe_attr(entry, :promoted_from),
          created_at: entry.created_at.iso8601,
          updated_at: entry.updated_at.iso8601,
          file_mtime: file_mtime.to_i,
          file_hash: file_hash.to_s,
          word_count: word_count.to_i,
          indexed_at: @clock.now.iso8601
        }
      end

      # Memo는 category/source/promoted_from이 없으므로 nil 반환.
      def maybe_attr(entry, name)
        entry.respond_to?(name) ? entry.public_send(name) : nil
      end

      # 기존 entry_tags 매핑 제거 후 새 태그로 다시 매핑.
      # 태그 정규화 테이블은 INSERT OR IGNORE (이미 있으면 재사용).
      def sync_tags(entry_id, tag_names)
        @db[:entry_tags].where(entry_id: entry_id).delete

        tag_names.each do |name|
          @db[:tags].insert_conflict.insert(name: name)
          tag_id = @db[:tags].where(name: name).get(:id)
          @db[:entry_tags].insert(entry_id: entry_id, tag_id: tag_id)
        end
      end

      def to_indexed_entry(row)
        IndexedEntry.new(
          id: row[:id],
          path: row[:path],
          mode: row[:mode].to_sym,
          title: row[:title],
          category: row[:category],
          template: row[:template],
          source: row[:source],
          promoted_from: row[:promoted_from],
          created_at: Time.iso8601(row[:created_at]),
          updated_at: Time.iso8601(row[:updated_at]),
          file_mtime: row[:file_mtime],
          file_hash: row[:file_hash],
          word_count: row[:word_count],
          indexed_at: Time.iso8601(row[:indexed_at]),
          tags: fetch_tags_for(row[:id])
        )
      end

      def fetch_tags_for(entry_id)
        @db[:tags]
          .join(:entry_tags, tag_id: :id)
          .where(Sequel[:entry_tags][:entry_id] => entry_id)
          .order(:name)
          .map { |r| r[:name] }
      end

      def validate_mode!(mode)
        return if [:memo, :note, :record].include?(mode)
        raise ArgumentError, "지원하지 않는 mode: #{mode.inspect}"
      end
    end
  end
end
