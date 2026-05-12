# frozen_string_literal: true

require "yaml"
require "fileutils"
require "digest"

module Sowing
  module Knowledge
    # Knowledge::PlanRepo — Plan 영속화 어댑터 (Phase R Stage 3 R3-T03).
    #
    # 책임:
    #   - 40_Plans/{period}/{date}-{hhmm}-{id4}.md 마크다운 파일 영속화
    #   - SQLite entries 인덱스 (mode='plan') 동시 upsert
    #
    # 옛 Sowing::Repositories::PlanRepo 와 책임 동일하지만 Knowledge BC 의 일부.
    # Knowledge::Plan 도메인 + subject 4축 처리.
    #
    # 파일명 규칙 (Phase 14 W32 — 같은 날짜 다중 plan 지원):
    #   daily/weekly/monthly: {plan_date}-{HHmm}-{ULID끝4}.md
    #   project/semester:     {plan_date}-{ULID끝4}.md (시간 prefix 불필요)
    class PlanRepo
      PLANS_DIR = "40_Plans"

      def initialize(vault_dir: nil, index_repo: nil, parser: nil)
        @vault_dir = Pathname.new((vault_dir || Core::Paths.vault_dir).to_s).expand_path
        @index_repo = index_repo || Repositories::IndexRepo.new
        @parser = parser || Core::Markdown::Parser.new
      end

      # @param plan [Sowing::Knowledge::Plan]
      # @return [Sowing::Knowledge::Plan]
      def create(plan)
        unless plan.is_a?(Plan)
          raise ArgumentError, "plan 은 Sowing::Knowledge::Plan 이어야 합니다 (받은 타입: #{plan.class})"
        end

        abs_path = resolve_path(plan)
        FileUtils.mkdir_p(abs_path.dirname)
        File.write(abs_path, serialize(plan), encoding: "UTF-8")

        upsert_index(plan, abs_path)
        plan
      end

      # @return [Sowing::Knowledge::Plan, nil]
      def find(id)
        indexed = @index_repo.find(id)
        return nil unless indexed
        return nil unless indexed.mode == :plan
        read_plan(@vault_dir.join(indexed.path))
      end

      # 최근 생성된 Plan 들 (created_at desc).
      # @return [Array<Sowing::Knowledge::Plan>]
      def recent(limit: 10)
        @index_repo.list(mode: :plan, limit: limit).filter_map do |e|
          read_plan(@vault_dir.join(e.path))
        end
      end

      private

      def resolve_path(plan)
        id_tail = plan.id.to_s[-4..]
        case plan.period
        when :project, :semester
          @vault_dir.join(PLANS_DIR, plan.period.to_s, "#{plan.plan_date}-#{id_tail}.md")
        else
          hhmm = plan.created_at.strftime("%H%M")
          @vault_dir.join(PLANS_DIR, plan.period.to_s, "#{plan.plan_date}-#{hhmm}-#{id_tail}.md")
        end
      end

      def serialize(plan)
        yaml = YAML.dump(plan.to_frontmatter).delete_prefix("---\n")
        "---\n#{yaml}---\n\n# #{plan.title}\n\n#{plan.body}\n"
      end

      def read_plan(abs_path)
        return nil unless abs_path.exist?
        parsed = @parser.parse(abs_path.read(encoding: "UTF-8"))
        fm = parsed.frontmatter
        body = parsed.body.sub(/\A# .+\n+/, "") # H1 제목 제거 (frontmatter 와 중복)

        Plan.new(
          id: Domain::ValueObjects::Ulid.parse(fm.fetch("id")),
          title: fm.fetch("title").to_s,
          body: body.chomp,
          tags: Domain::ValueObjects::TagSet.new(fm["tags"] || []),
          template: fm["template"],
          period: fm.fetch("period").to_sym,
          plan_date: fm.fetch("plan_date").to_s,
          done: fm["done"] == true,
          subject: fm["subject"]&.to_sym,
          created_at: Time.iso8601(fm.fetch("created_at")),
          updated_at: Time.iso8601(fm.fetch("updated_at"))
        )
      end

      # entries 인덱싱 — 같은 path 의 옛 row 가 다른 id 면 삭제 후 새 id insert
      # (사용자가 같은 period+date 로 새 plan 제출 시 path 재사용 시나리오).
      def upsert_index(plan, abs_path)
        rel_path = abs_path.relative_path_from(@vault_dir).to_s
        existing = @index_repo.find_by_path(rel_path)
        @index_repo.delete(existing.id) if existing && existing.id.to_s != plan.id.to_s

        @index_repo.upsert(
          plan,
          path: rel_path,
          file_mtime: abs_path.mtime.to_i,
          file_hash: Digest::SHA256.hexdigest(abs_path.binread)[0, 16],
          word_count: plan.body.split.size
        )
      rescue Sequel::CheckConstraintViolation
        # migration 미적용 시 graceful — file 은 저장됨
        nil
      end
    end
  end
end
