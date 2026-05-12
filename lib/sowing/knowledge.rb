# frozen_string_literal: true

module Sowing
  # Bounded Context #2 — Knowledge (지식·기록·계획).
  #
  # 책임: 정리된 기록·계획 + Archive (이관) 관리.
  # subject 4축 명시 분류 + 자유 카테고리 공존.
  #
  # 도메인:
  #   - Knowledge::Record — Note + Record 흡수 (ADR-015, R3-T01)
  #   - Knowledge::Plan — 5 period (daily/weekly/monthly/project/semester, R3-T02)
  #   - Knowledge::RecordRepo / PlanRepo — 영속화 어댑터 (R3-T03)
  #
  # Archive (ADR-017): archived_at + archive_reason 메타데이터.
  # 일상 회상 (검색·합성기·view_recent) 에서 자동 제외, 보관함 (`/archive`)
  # 페이지에서만 노출. — R3-T05 migration 009 에서 구현.
  #
  # 의존: Core + Capture (subject DRY).
  module Knowledge
    @repo_mutex = Mutex.new

    class << self
      # === Record ============================================================

      # @param title [String]
      # @param body [String]
      # @param category [String] 자유 텍스트 (옛 Record 와 동일)
      # @param source [String, nil] 옛 Note 의 source 흡수 (선택)
      # @param subject [Symbol, nil] 4축 ENUM (ADR-016)
      # @param tags [Array<String>, TagSet]
      # @return [Sowing::Knowledge::Record]
      def create_record(title:, body:, category:, source: nil, subject: nil,
        tags: [], template: nil, promoted_from: nil,
        id: nil, created_at: nil)
        raise ArgumentError, "title 은 빈 문자열일 수 없습니다" if title.to_s.strip.empty?
        raise ArgumentError, "body 는 빈 문자열일 수 없습니다" if body.to_s.strip.empty?
        raise ArgumentError, "category 는 빈 문자열일 수 없습니다" if category.to_s.strip.empty?

        record = Record.new(
          id: id || Domain::ValueObjects::Ulid.generate,
          body: body,
          created_at: created_at || Time.now,
          title: title,
          tags: tags.is_a?(Domain::ValueObjects::TagSet) ? tags : Domain::ValueObjects::TagSet.new(tags),
          template: template,
          category: category,
          source: source,
          promoted_from: promoted_from,
          subject: subject
        )
        record_repo.create(record)
      end

      # === Plan ==============================================================

      # @param title [String]
      # @param period [Symbol] :daily|:weekly|:monthly|:project|:semester
      # @param plan_date [String] period 별 형식 (YYYY-MM-DD, YYYY-Www, slug 등)
      # @param body [String]
      # @param subject [Symbol, nil] 4축 ENUM
      # @param done [Boolean]
      # @return [Sowing::Knowledge::Plan]
      def create_plan(title:, period:, plan_date:, body: "", subject: nil,
        tags: [], template: nil, done: false,
        id: nil, created_at: nil)
        raise ArgumentError, "title 은 빈 문자열일 수 없습니다" if title.to_s.strip.empty?
        raise ArgumentError, "plan_date 는 빈 문자열일 수 없습니다" if plan_date.to_s.strip.empty?

        plan = Plan.new(
          id: id || Domain::ValueObjects::Ulid.generate,
          title: title,
          body: body,
          period: period,
          plan_date: plan_date,
          created_at: created_at || Time.now,
          tags: tags.is_a?(Domain::ValueObjects::TagSet) ? tags : Domain::ValueObjects::TagSet.new(tags),
          template: template,
          done: done,
          subject: subject
        )
        plan_repo.create(plan)
      end

      # === 조회 ==============================================================

      # 단건 조회 — Record 또는 Plan (mode 자동 판별).
      # @return [Sowing::Knowledge::Record, Sowing::Knowledge::Plan, nil]
      def find(id)
        record_repo.find(id) || plan_repo.find(id)
      end

      # 최근 생성된 Record (Plan 제외).
      def recent_records(limit: 10)
        record_repo.recent(limit: limit)
      end

      # 최근 생성된 Plan (Record 제외).
      def recent_plans(limit: 10)
        plan_repo.recent(limit: limit)
      end

      # === Archive (R3-T05 에서 실 구현) ====================================

      def archive(entry_id, reason:)
        raise NotImplementedError, "Stage 3 R3-T05 에 구현 (ADR-017 migration 009)"
      end

      def unarchive(entry_id)
        raise NotImplementedError, "Stage 3 R3-T05 에 구현"
      end

      # === DI 진입점 (테스트 격리·repo 캐싱) ================================

      def record_repo
        @repo_mutex.synchronize { @record_repo ||= RecordRepo.new }
      end

      def plan_repo
        @repo_mutex.synchronize { @plan_repo ||= PlanRepo.new }
      end

      attr_writer :record_repo, :plan_repo

      def reset_repos!
        @repo_mutex.synchronize {
          @record_repo = nil
          @plan_repo = nil
        }
      end
    end
  end
end
