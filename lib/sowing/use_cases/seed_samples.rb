# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "pathname"
require "time"

module Sowing
  module UseCases
    # `templates/samples/*.md` 12개를 사용자 vault에 시드 (W7-T03).
    #
    # 호출 경로:
    #   - 온보딩 4단계에서 사용자가 동의한 경우 (W7-T01 OnboardingController)
    #   - `bundle exec rake vault:seed` 수동 호출
    #
    # 중복 시드 방지: 각 샘플의 ULID로 IndexRepo.find 조회 → 이미 있으면 skip.
    # 마크다운 SoT 원칙: VaultRepo.write로 실제 파일 작성 + Persistence#update_index!.
    class SeedSamples
      include Dry::Monads[:result]
      include Persistence

      DEFAULT_SAMPLES_DIR = File.expand_path("../../../templates/samples", __dir__)

      def initialize(
        vault_repo: nil,
        index_repo: nil,
        samples_dir: DEFAULT_SAMPLES_DIR
      )
        @vault_repo = vault_repo || Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        @index_repo = index_repo || Repositories::IndexRepo.new
        @samples_dir = Pathname.new(samples_dir.to_s)
      end

      # @return [Result] Success({seeded:, skipped:, total:}) | Failure(:samples_dir_missing)
      def call
        return Failure(:samples_dir_missing) unless @samples_dir.exist?

        files = Dir.glob(@samples_dir.join("*.md")).sort
        seeded = 0
        skipped = 0

        files.each do |path|
          entry = parse_to_domain(File.read(path))
          if @index_repo.find(entry.id)
            skipped += 1
          else
            persist!(entry)
            seeded += 1
          end
        end

        Success(seeded: seeded, skipped: skipped, total: files.size)
      end

      private

      def parse_to_domain(raw)
        parsed = FrontMatterParser::Parser.new(:md).call(raw)
        fm = parsed.front_matter
        body = parsed.content.to_s.chomp

        common = {
          id: Domain::ValueObjects::Ulid.parse(fm.fetch("id")),
          body: body,
          created_at: Time.iso8601(fm.fetch("created_at")),
          updated_at: Time.iso8601(fm.fetch("updated_at")),
          title: fm["title"],
          tags: Domain::ValueObjects::TagSet.new(fm["tags"] || []),
          template: fm["template"]
        }

        case fm.fetch("mode")
        when "memo"
          Domain::Memo.new(**common)
        when "note"
          Domain::Note.new(**common.merge(
            category: fm.fetch("category"),
            source: fm.fetch("source"),
            promoted_from: fm["promoted_from"]
          ))
        when "record"
          Domain::Record.new(**common.merge(
            category: fm.fetch("category"),
            promoted_from: fm["promoted_from"]
          ))
        else
          raise ArgumentError, "지원하지 않는 mode: #{fm["mode"].inspect}"
        end
      end
    end
  end
end
