# frozen_string_literal: true

require "yaml"
require "pathname"
require "fileutils"
require "digest"
require "front_matter_parser"

module Sowing
  module Repositories
    # Plan 전용 영속화 어댑터 (Phase 13 W27-T01).
    #
    # 책임:
    #   - 40_Plans/{period}/{plan_date}.md 마크다운 파일 읽기/쓰기
    #   - Plan ↔ frontmatter+body 변환
    #   - 영구 삭제 0 (휴지통 이동 — W27-T02 에 통합)
    #
    # 경로 규칙:
    #   - daily:   40_Plans/daily/{YYYY-MM-DD}.md     (날짜당 1 파일)
    #   - weekly:  40_Plans/weekly/{YYYY-Www}.md      (주당 1 파일)
    #   - monthly: 40_Plans/monthly/{YYYY-MM}.md      (월당 1 파일)
    #
    # 한 period+date 당 단일 파일 — 여러 계획을 한 파일의 마크다운 todo list 로
    # 작성. 옵시디언에서 그대로 열어 [ ] / [x] 토글 가능.
    #
    # IndexRepo·entries 테이블 통합은 W27-T03 (마이그레이션 008).
    # 본 repo 는 파일 + entries 인덱스 동시 영속화 — Memo/Note/Record 와 동등.
    class PlanRepo
      PLANS_DIR = "40_Plans"

      attr_reader :vault_dir

      def initialize(vault_dir:, index_repo: nil)
        @vault_dir = Pathname.new(vault_dir.to_s).expand_path
        @index_repo = index_repo
      end

      # @param plan [Sowing::Domain::Plan]
      # @return [Pathname] 저장된 절대 경로
      def write(plan)
        target = resolve_path(plan)
        FileUtils.mkdir_p(target.dirname)
        File.write(target, serialize(plan), encoding: "UTF-8")
        upsert_index(plan, target)
        target
      end

      # @return [Sowing::Domain::Plan, nil] 못 찾으면 nil
      def read(path)
        full = absolute(path)
        return nil unless full.exist?
        raw = File.read(full, encoding: "UTF-8")
        parsed = FrontMatterParser::Parser.new(:md).call(raw)
        reconstruct(parsed.front_matter, parsed.content)
      end

      # period 별 plan 목록 (최신순 — 파일명 기준).
      # @param period [Symbol] :daily|:weekly|:monthly
      # @return [Array<Sowing::Domain::Plan>]
      def list_by_period(period)
        dir = @vault_dir.join(PLANS_DIR, period.to_s)
        return [] unless dir.exist?
        Dir.glob(dir.join("*.md"))
          .sort
          .reverse
          .filter_map { |p| read(p) }
      end

      # 모든 period 의 plan 합본 (대시보드 위젯·통합 검색용).
      def list_all
        Domain::Plan::PERIODS.flat_map { |p| list_by_period(p) }
      end

      # id 로 단건 조회 — 모든 period 디렉토리 스캔.
      # PoC 라 단순 구현. T02 에서 entries 인덱스 통합 시 O(1).
      def find_by_id(id)
        Domain::Plan::PERIODS.each do |period|
          dir = @vault_dir.join(PLANS_DIR, period.to_s)
          next unless dir.exist?
          Dir.glob(dir.join("*.md")).each do |path|
            plan = read(path)
            return [plan, Pathname.new(path)] if plan && plan.id.to_s == id.to_s
          end
        end
        nil
      end

      # 완료 토글 — frontmatter done 만 뒤집어 재저장.
      # @return [Sowing::Domain::Plan, nil] 토글 후 새 Plan (못 찾으면 nil)
      def toggle_done(id)
        result = find_by_id(id)
        return nil unless result
        plan, path = result
        toggled = Domain::Plan.new(
          id: plan.id,
          title: plan.title,
          body: plan.body,
          tags: plan.tags,
          template: plan.template,
          period: plan.period,
          plan_date: plan.plan_date,
          done: !plan.done,
          created_at: plan.created_at,
          updated_at: Time.now
        )
        File.write(path, serialize(toggled), encoding: "UTF-8")
        upsert_index(toggled, path)
        toggled
      end

      private

      # W27-T03 — entries 테이블에도 plan 인덱싱.
      # IndexRepo 가 nil 이면 lazy 생성. mode='plan' 으로 upsert.
      # 인덱싱 실패해도 vault 파일 쓰기는 성공 — graceful (마이그레이션 미적용 시).
      #
      # Overwrite semantics (Phase 14 hotfix):
      # 같은 path 의 기존 entry 가 다른 id 라면 (= 사용자가 같은 period+date 로 새 plan
      # 제출) 기존 row 삭제 후 새 id 로 insert. file 은 이미 덮어써짐 — entries 도 정합.
      # 이유: 같은 period+date 는 1 파일 1 plan 이 의도 (daily/2026-05-11.md 처럼).
      def upsert_index(plan, absolute_path)
        repo = @index_repo || IndexRepo.new
        relative_path = Pathname.new(absolute_path.to_s).relative_path_from(@vault_dir).to_s

        existing = repo.find_by_path(relative_path)
        repo.delete(existing.id) if existing && existing.id.to_s != plan.id.to_s

        repo.upsert(
          plan,
          path: relative_path,
          file_mtime: File.mtime(absolute_path).to_i,
          file_hash: Digest::SHA256.hexdigest(File.binread(absolute_path))[0, 16],
          word_count: plan.body.split.size
        )
      rescue Sequel::CheckConstraintViolation
        # 마이그레이션 미적용 시 무시 — file 은 저장됨, IndexRepo 통합만 skip
        nil
      end

      # 파일명 규칙 (Phase 14 W32 — 같은 날짜에 여러 plan 지원):
      #   daily/weekly/monthly: {plan_date}-{HHmm}-{ULID끝4}.md
      #     예: 40_Plans/daily/2026-05-11-0930-X4F2.md
      #   project/semester: {plan_date}-{ULID끝4}.md  (시간 prefix 불필요)
      # ULID 끝 4 자리 = Crockford Base32 — 같은 분에 여러 plan 만들어도 충돌 0.
      def resolve_path(plan)
        id_tail = plan.id.to_s[-4..]
        case plan.period
        when :project, :semester
          # project = slug 가 이미 unique, semester = YYYY-Sn (1 학기 1 파일 의도)
          # 같은 slug/semester 에 여러 plan 가능하도록 끝 4자리 추가
          @vault_dir.join(PLANS_DIR, plan.period.to_s, "#{plan.plan_date}-#{id_tail}.md")
        else
          # daily/weekly/monthly — 시간 prefix + ULID 끝
          hhmm = plan.created_at.strftime("%H%M")
          @vault_dir.join(PLANS_DIR, plan.period.to_s, "#{plan.plan_date}-#{hhmm}-#{id_tail}.md")
        end
      end

      def absolute(path)
        pathname = Pathname.new(path.to_s)
        pathname.absolute? ? pathname : @vault_dir.join(pathname)
      end

      def serialize(plan)
        yaml = YAML.dump(plan.to_frontmatter).delete_prefix("---\n")
        "---\n#{yaml}---\n\n# #{plan.title}\n\n#{plan.body}\n"
      end

      def reconstruct(frontmatter, body)
        Domain::Plan.new(
          id: Domain::ValueObjects::Ulid.new(frontmatter["id"]),
          title: frontmatter["title"].to_s,
          body: body.to_s.sub(/\A# .+\n+/, ""), # H1 제목 제거 (frontmatter 와 중복)
          tags: Domain::ValueObjects::TagSet.new(frontmatter["tags"] || []),
          template: frontmatter["template"],
          period: frontmatter["period"].to_sym,
          plan_date: frontmatter["plan_date"].to_s,
          done: frontmatter["done"] == true,
          created_at: parse_time(frontmatter["created_at"]),
          updated_at: parse_time(frontmatter["updated_at"])
        )
      end

      def parse_time(value)
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end
    end
  end
end
