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
      # 같은 id가 있으면 모든 컬럼을 덮어쓰고, 태그·링크 매핑도 새로 갱신.
      # 트랜잭션으로 entries + entry_tags + tags + links 원자적 갱신.
      # @return [IndexedEntry]
      def upsert(entry, path:, file_mtime:, file_hash:, word_count: 0)
        row = build_row(entry, path: path, file_mtime: file_mtime, file_hash: file_hash, word_count: word_count)

        @db.transaction do
          @db[:entries].insert_conflict(target: :id, update: row).insert(row)
          sync_tags(entry.id.to_s, frontmatter_tags: entry.tags.to_a, body: entry.body)
          sync_outbound_links(entry)
          nullify_stale_inbound_links(entry)
          relink_broken_to(entry)
          sync_fts(entry)
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

      # 파일 경로(vault 기준 상대 경로)로 entry 조회 — 외부 변경 동기화에 사용 (W5-T02).
      # @param path [String, Pathname]
      # @return [IndexedEntry, nil]
      def find_by_path(path)
        row = @db[:entries].where(path: path.to_s).first
        return nil unless row
        to_indexed_entry(row)
      end

      # 인덱스에 등록된 모든 path (vault 기준 상대 경로) — 부팅 시 일관성 검증용 (W5-T04).
      # @return [Array<String>]
      def all_paths
        @db[:entries].select_map(:path)
      end

      # @param mode     [Symbol] :memo, :note, :record
      # @param category [String, nil] category 컬럼 정확 일치 필터
      # @param limit    [Integer, nil] 가져올 최대 행 수
      # @param offset   [Integer, nil] 건너뛸 행 수
      # @return [Array<IndexedEntry>] created_at 내림차순
      def list(mode:, category: nil, limit: nil, offset: nil)
        validate_mode!(mode)
        # 같은 초에 다수 entry가 생성되면 created_at만으로는 ordering이 불안정.
        # ULID id는 lexicographically time-monotonic이므로 보조 정렬로 안정성 확보.
        ds = @db[:entries].where(mode: mode.to_s)
        ds = ds.where(category: category) if category
        ds = ds.order(Sequel.desc(:created_at), Sequel.desc(:id))
        ds = ds.limit(limit) if limit
        ds = ds.offset(offset) if offset
        ds.map { |row| to_indexed_entry(row) }
      end

      # @param mode     [Symbol]
      # @param category [String, nil] 동일 필터를 적용한 후 행 수
      # @return [Integer] 해당 모드 row 수
      def count(mode:, category: nil)
        validate_mode!(mode)
        ds = @db[:entries].where(mode: mode.to_s)
        ds = ds.where(category: category) if category
        ds.count
      end

      # 사용된 적 있는 distinct category 이름 (정렬). Record처럼 자유 텍스트 카테고리에서
      # datalist 자동완성·필터 탭에 사용.
      # @return [Array<String>]
      def distinct_categories(mode:)
        validate_mode!(mode)
        @db[:entries].where(mode: mode.to_s).exclude(category: nil).distinct.select_order_map(:category)
      end

      # 모든 모드의 distinct category 합집합 (검색 화면 datalist).
      # @return [Array<String>]
      def all_distinct_categories
        @db[:entries].exclude(category: nil).distinct.select_order_map(:category)
      end

      MODE_PRIORITY = {"record" => 1, "note" => 2, "memo" => 3}.freeze
      private_constant :MODE_PRIORITY

      # 태그 클라우드 — 모든 tags를 사용 횟수 desc + 이름 asc로.
      # @return [Array<Hash>] {name, count}
      def tag_cloud
        @db[:tags]
          .left_join(:entry_tags, tag_id: :id)
          .group_and_count(Sequel[:tags][:name])
          .order(Sequel.desc(:count), Sequel[:tags][:name])
          .all
      end

      # 태그명 자동완성 — q substring (case-insensitive 자동, COLLATE NOCASE).
      # @return [Array<String>]
      def complete_tags(q:, limit: 25)
        q = q.to_s.strip
        ds = @db[:tags]
        ds = ds.where(Sequel.like(:name, "%#{q}%")) unless q.empty?
        ds.order(:name).limit(limit).select_map(:name)
      end

      # 위키링크 자동완성 후보 검색 (ADR-004 / W3-T03).
      # 정렬: 모드 우선(record > note > memo) → created_at desc → id desc(보조).
      # q가 비어있으면 모든 모드 최근순. q가 있으면 entries.title의 substring 매칭만
      # (메모는 title이 nil이라 q 매칭에서 제외 — 본문 매칭은 W4 FTS에서 도입 예정).
      #
      # @param q [String]
      # @param limit [Integer]
      # @return [Array<Hash>] entries 컬럼 그대로 (path, title, mode, created_at 등)
      def complete(q:, limit: 25)
        q = q.to_s.strip
        ds = @db[:entries]

        unless q.empty?
          # 사용자 입력에 %/_ 가 있으면 literal 매칭 못 함 (W3-T03 한계).
          # FTS 도입 시 본 한계 해소 예정.
          ds = ds.where(Sequel.like(:title, "%#{q}%"))
        end

        ds.order(
          Sequel.case(MODE_PRIORITY, 4, :mode),
          Sequel.desc(:created_at),
          Sequel.desc(:id)
        ).limit(limit).all
      end

      # ──────────────────────────────────────────
      # 전문 검색 (W4-T01 FTS5 trigram + W4-T02 한국어 LIKE 폴백)
      # ──────────────────────────────────────────

      KOREAN_RATIO_THRESHOLD = 0.30
      LIKE_ESCAPE_CHAR = "!"
      private_constant :KOREAN_RATIO_THRESHOLD, :LIKE_ESCAPE_CHAR

      # 통합 검색 진입점. q의 한글 비율에 따라 자동 라우팅.
      # 한글 비율 ≥ 30%이면 LIKE 폴백 (trigram의 한국어 2글자 한계 보강),
      # 그 외(영문 위주)는 FTS5 trigram.
      # @param q [String]
      # @param limit [Integer]
      # @return [Array<IndexedEntry>]
      def search(q:, limit: 50)
        q = q.to_s.strip
        return [] if q.empty?

        if korean_dominant?(q)
          search_like(q: q, limit: limit)
        else
          search_full_text(q: q, limit: limit)
        end
      end

      # entries_fts에서 q를 매칭하는 entries 반환 (created_at desc).
      # trigram 한계: 3글자 이상 query만 정확 매칭. 한국어 2글자는 search_like가 보강.
      # @return [Array<IndexedEntry>]
      def search_full_text(q:, limit: 50)
        q = q.to_s.strip
        return [] if q.empty?

        ids = @db[:entries_fts]
          .where(Sequel.lit("entries_fts MATCH ?", q))
          .limit(limit)
          .select_map(:id)
        return [] if ids.empty?

        rows = @db[:entries]
          .where(id: ids)
          .order(Sequel.desc(:created_at), Sequel.desc(:id))
          .all
        rows.map { |row| to_indexed_entry(row) }
      end

      # LIKE 폴백 — entries_fts.title/body에서 substring 매칭.
      # 한국어 2글자 등 trigram이 못 잡는 케이스를 위해. 5,000건 < 500ms 목표.
      # @return [Array<IndexedEntry>]
      def search_like(q:, limit: 50)
        q = q.to_s.strip
        return [] if q.empty?

        pattern = "%#{escape_like(q)}%"
        ids = @db[:entries_fts]
          .where(
            Sequel.lit(
              "title LIKE ? ESCAPE '#{LIKE_ESCAPE_CHAR}' OR body LIKE ? ESCAPE '#{LIKE_ESCAPE_CHAR}'",
              pattern, pattern
            )
          )
          .limit(limit)
          .select_map(:id)
        return [] if ids.empty?

        rows = @db[:entries]
          .where(id: ids)
          .order(Sequel.desc(:created_at), Sequel.desc(:id))
          .all
        rows.map { |row| to_indexed_entry(row) }
      end

      # 통합 필터 검색 (W4-T03). q + mode + category + tag + 날짜 범위 모두 결합.
      # 모든 필터는 AND. tag는 entry_tags+tags JOIN. q는 search 라우팅(한글 비율 자동).
      # @return [Array<IndexedEntry>]
      def search_with_filters(q: nil, mode: nil, category: nil, tag: nil,
        from: nil, to: nil, limit: 50, offset: 0)
        ds = filtered_dataset(q: q, mode: mode, category: category, tag: tag, from: from, to: to)
        return [] if ds.nil?

        ds.order(Sequel.desc(Sequel[:entries][:created_at]), Sequel.desc(Sequel[:entries][:id]))
          .limit(limit)
          .offset(offset)
          .all
          .map { |row| to_indexed_entry(row) }
      end

      # @return [Integer]
      def count_with_filters(q: nil, mode: nil, category: nil, tag: nil, from: nil, to: nil)
        ds = filtered_dataset(q: q, mode: mode, category: category, tag: tag, from: from, to: to)
        return 0 if ds.nil?
        ds.count
      end

      # ──────────────────────────────────────────
      # 위키링크 그래프 (SPEC §8.3 links 테이블)
      # ──────────────────────────────────────────

      # 특정 entry가 가진 outbound 링크 목록.
      # @param source_id [String, Sowing::Domain::ValueObjects::Ulid]
      # @return [Array<Hash>] {source_id, target_id, target_text} (target_text 오름차순)
      def links_from(source_id)
        @db[:links].where(source_id: source_id.to_s).order(:target_text).all
      end

      # 특정 entry로 들어오는 inbound 링크 (backlinks).
      # @return [Array<Hash>]
      def links_to(target_id)
        @db[:links].where(target_id: target_id.to_s).order(:source_id).all
      end

      # 깨진 링크 (target_id IS NULL) — 아직 매칭되는 entry가 없는 위키링크.
      # @return [Array<Hash>]
      def broken_links
        @db[:links].where(target_id: nil).order(:source_id, :target_text).all
      end

      # @param id [Sowing::Domain::ValueObjects::Ulid, String]
      # @return [Boolean] 삭제 여부 (entries 행이 실제로 있었는지)
      # entries_fts는 entries와 별도 테이블이므로 명시 정리 (FK CASCADE 미적용).
      def delete(id)
        id_str = id.to_s
        deleted = false
        @db.transaction do
          @db[:entries_fts].where(id: id_str).delete
          deleted = @db[:entries].where(id: id_str).delete > 0
        end
        deleted
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
      # frontmatter tags ∪ body의 #태그를 모두 정규화 후 union하여 인덱싱 (W3-T05).
      # 태그 정규화 테이블은 INSERT OR IGNORE (이미 있으면 재사용).
      def sync_tags(entry_id, frontmatter_tags:, body:)
        @db[:entry_tags].where(entry_id: entry_id).delete

        body_tags = Infrastructure::Markdown::Hashtag.extract(body.to_s)
        all_tags = (frontmatter_tags + body_tags).map { |t| t.to_s.strip.downcase }
          .reject(&:empty?).uniq

        all_tags.each do |name|
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

      # ── 위키링크 그래프 동기화 ─────────────────────

      # entry.body에서 위키링크 target을 추출하여 links 테이블에 동기화.
      # 기존 source의 모든 row를 제거하고 새로 insert (멱등).
      # title 정확 일치로 target_id 매칭 — 일치 안 되면 NULL (broken).
      def sync_outbound_links(entry)
        source_id = entry.id.to_s
        @db[:links].where(source_id: source_id).delete

        targets = Infrastructure::Markdown::WikiLink.extract(entry.body).map(&:target).uniq
        targets.each do |target_text|
          target_id = lookup_target_id_by_title(target_text)
          @db[:links].insert(
            source_id: source_id,
            target_id: target_id,
            target_text: target_text
          )
        end
      end

      # entry의 title이 변경되면 옛 title로 가리키던 inbound link들은 broken으로 강등.
      # 그 다음 relink_broken_to가 새 title과 매칭되는 broken을 다시 fix.
      def nullify_stale_inbound_links(entry)
        return unless entry.title

        @db[:links]
          .where(target_id: entry.id.to_s)
          .exclude(target_text: entry.title)
          .update(target_id: nil)
      end

      # 새 entry/갱신된 title과 일치하는 broken link들을 자동 fix.
      def relink_broken_to(entry)
        return unless entry.title

        @db[:links]
          .where(target_id: nil, target_text: entry.title)
          .update(target_id: entry.id.to_s)
      end

      def lookup_target_id_by_title(title)
        @db[:entries].where(title: title).get(:id)
      end

      # 한글 비율이 임계 이상이면 LIKE 폴백을 선택 (trigram 한계 보강).
      def korean_dominant?(text)
        return false if text.empty?
        korean_chars = text.scan(/\p{Hangul}/).size
        (korean_chars.to_f / text.length) >= KOREAN_RATIO_THRESHOLD
      end

      # 통합 필터 데이터셋. q가 있고 매칭 0건이면 nil 반환 (caller가 빈 결과로 처리).
      def filtered_dataset(q:, mode:, category:, tag:, from:, to:)
        ds = @db[:entries]

        ds = ds.where(Sequel[:entries][:mode] => mode.to_s) if mode
        ds = ds.where(Sequel[:entries][:category] => category) if category && !category.to_s.strip.empty?

        if tag && !tag.to_s.strip.empty?
          tag_normalized = tag.to_s.strip.downcase
          ds = ds
            .join(:entry_tags, entry_id: Sequel[:entries][:id])
            .join(:tags, id: Sequel[:entry_tags][:tag_id])
            .where(Sequel[:tags][:name] => tag_normalized)
            .select_all(:entries)
        end

        if from && to
          ds = ds.where(Sequel[:entries][:created_at] => from.iso8601..to.iso8601)
        end

        if q && !q.to_s.strip.empty?
          q_clean = q.to_s.strip
          matched_ids = if korean_dominant?(q_clean)
            like_match_ids(q_clean)
          else
            fts_match_ids(q_clean)
          end
          return nil if matched_ids.empty?
          ds = ds.where(Sequel[:entries][:id] => matched_ids)
        end

        ds
      end

      def fts_match_ids(q)
        @db[:entries_fts]
          .where(Sequel.lit("entries_fts MATCH ?", q))
          .select_map(:id)
      end

      def like_match_ids(q)
        pattern = "%#{escape_like(q)}%"
        @db[:entries_fts]
          .where(
            Sequel.lit(
              "title LIKE ? ESCAPE '#{LIKE_ESCAPE_CHAR}' OR body LIKE ? ESCAPE '#{LIKE_ESCAPE_CHAR}'",
              pattern, pattern
            )
          )
          .select_map(:id)
      end

      # LIKE 패턴에서 wildcard 문자(%, _) 및 escape 문자(!) 자체를 literal로 처리.
      def escape_like(text)
        text.gsub(/[%_#{Regexp.escape(LIKE_ESCAPE_CHAR)}]/o) { |c| "#{LIKE_ESCAPE_CHAR}#{c}" }
      end

      # ── FTS5 동기화 ────────────────────────────

      # entries_fts에 entry의 title·body를 동기화 (delete + insert 패턴).
      # FTS5의 UPDATE는 까다로우므로 안전하게 행 교체.
      def sync_fts(entry)
        id = entry.id.to_s
        @db[:entries_fts].where(id: id).delete
        @db[:entries_fts].insert(
          id: id,
          title: entry.title,
          body: entry.body
        )
      end

      def validate_mode!(mode)
        return if [:memo, :note, :record].include?(mode)
        raise ArgumentError, "지원하지 않는 mode: #{mode.inspect}"
      end
    end
  end
end
