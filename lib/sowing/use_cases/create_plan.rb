# frozen_string_literal: true

require "dry/monads"

module Sowing
  module UseCases
    # Plan 생성 (Phase 13 W27-T01).
    #
    # 흐름: 입력 검증 → 도메인 Plan 생성 → PlanRepo.write
    # Memo/Note/Record 와 달리 IndexRepo 통합은 W27-T02 — 본 PoC 는 파일만.
    class CreatePlan
      include Dry::Monads[:result]

      def initialize(plan_repo:, clock: Time)
        @plan_repo = plan_repo
        @clock = clock
      end

      # @param title [String]    계획 제목
      # @param period [Symbol]   :daily|:weekly|:monthly
      # @param plan_date [String] YYYY-MM-DD / YYYY-Www / YYYY-MM
      # @param body [String]     본문 (마크다운 — todo list 등)
      # @param tags [Array<String>]
      # @return [Dry::Monads::Result] Success(Plan) | Failure(Symbol)
      def call(title:, period:, plan_date:, body: "", tags: [])
        return Failure(:empty_title) if title.to_s.strip.empty?
        return Failure(:invalid_period) unless Domain::Plan::PERIODS.include?(period.to_sym)
        return Failure(:empty_plan_date) if plan_date.to_s.strip.empty?
        return Failure(:invalid_plan_date) unless plan_date_format_ok?(period, plan_date)

        plan = Domain::Plan.new(
          id: Domain::ValueObjects::Ulid.generate,
          title: title.strip,
          body: body.to_s,
          period: period.to_sym,
          plan_date: plan_date.to_s,
          tags: Domain::ValueObjects::TagSet.new(tags),
          done: false,
          created_at: @clock.now
        )

        @plan_repo.write(plan)
        Success(plan)
      end

      private

      def plan_date_format_ok?(period, date)
        case period.to_sym
        when :daily    then date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        when :weekly   then date.match?(/\A\d{4}-W\d{2}\z/)
        when :monthly  then date.match?(/\A\d{4}-\d{2}\z/)
        when :project  then date.match?(/\A[\w가-힣\-]+\z/) # slug — kebab, 한글, 영숫자, _
        when :semester then date.match?(/\A\d{4}-S[12]\z/)  # 2026-S1 = 1학기, 2026-S2 = 2학기
        else false
        end
      end
    end
  end
end
