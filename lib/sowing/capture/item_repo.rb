# frozen_string_literal: true

module Sowing
  module Capture
    # Capture::ItemRepo — Item 영속화 어댑터 (Phase R Stage 2 R2-T02).
    #
    # 책임:
    #   - 신규 Capture::Item 의 파일 저장 (옵시디언 00_Inbox/) + SQLite 인덱싱
    #   - id / 최근순 조회 시 frontmatter 재파싱으로 subject 복원
    #
    # 설계 결정:
    #   - VaultRepo / IndexRepo 를 직접 사용 (composition over inheritance).
    #   - Item.mode == :memo 이므로 VaultRepo 의 :memo 분기 (00_Inbox/) 그대로 활용.
    #   - IndexRepo 의 entries 테이블에는 subject 컬럼이 아직 없음 (R2-T05 마이그레이션 008
    #     에서 추가 예정). 그 전까지는 frontmatter 재파싱으로 subject 회수.
    #
    # 의존: Core (Parser/Filesystem), Capture::Item, Domain::ValueObjects.
    #       Domain::Memo 와 무관 — Item 은 옛 Memo 의 superset 으로 독립.
    class ItemRepo
      def initialize(vault_repo: nil, index_repo: nil, parser: nil)
        @vault_repo = vault_repo || Repositories::VaultRepo.new(vault_dir: Core::Paths.vault_dir)
        @index_repo = index_repo || Repositories::IndexRepo.new
        @parser = parser || Core::Markdown::Parser.new
      end

      # Item 을 파일로 저장 + 인덱스 upsert.
      # @param item [Sowing::Capture::Item]
      # @return [Sowing::Capture::Item] 그대로 반환 (불변 객체)
      def create(item)
        unless item.is_a?(Item)
          raise ArgumentError, "item 은 Sowing::Capture::Item 이어야 합니다 (받은 타입: #{item.class})"
        end

        abs_path = @vault_repo.write(item)
        rel_path = abs_path.relative_path_from(@vault_repo.vault_dir).to_s

        @index_repo.upsert(
          item,
          path: rel_path,
          file_mtime: abs_path.mtime.to_i,
          file_hash: @vault_repo.file_hash(abs_path),
          word_count: word_count(item.body)
        )

        item
      end

      # ULID 로 Item 조회. 다른 mode (note/record) 의 entry 면 nil.
      # @param id [String, Sowing::Domain::ValueObjects::Ulid]
      # @return [Sowing::Capture::Item, nil]
      def find(id)
        indexed = @index_repo.find(id)
        return nil unless indexed
        return nil unless indexed.mode == :memo
        read_item(indexed.path)
      end

      # 최근 생성된 Item 들 (created_at desc).
      # @param limit [Integer]
      # @return [Array<Sowing::Capture::Item>]
      def recent(limit: 10)
        @index_repo.list(mode: :memo, limit: limit).map { |e| read_item(e.path) }
      end

      private

      # vault-기준 상대 경로 → Item 재구성.
      # frontmatter 의 subject 키를 Symbol 로 복원 (없으면 nil).
      def read_item(rel_path)
        abs = @vault_repo.vault_dir.join(rel_path)
        parsed = @parser.parse(abs.read(encoding: "UTF-8"))
        fm = parsed.frontmatter

        Item.new(
          id: Domain::ValueObjects::Ulid.parse(fm.fetch("id")),
          body: parsed.body.chomp,
          created_at: Time.iso8601(fm.fetch("created_at")),
          updated_at: Time.iso8601(fm.fetch("updated_at")),
          title: fm["title"],
          tags: Domain::ValueObjects::TagSet.new(fm["tags"] || []),
          template: fm["template"],
          subject: fm["subject"]&.to_sym
        )
      end

      def word_count(body)
        body.to_s.split(/\s+/).reject(&:empty?).size
      end
    end
  end
end
