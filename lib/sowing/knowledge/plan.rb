# frozen_string_literal: true

module Sowing
  module Knowledge
    # Knowledge::Plan — 미래 계획 (4번째 1급 mode, ADR-014).
    #
    # 옛 Domain::Plan 의 후신 (Phase R Stage 3 R3-T02). Knowledge BC 로 이전 +
    # subject 4축 (ADR-016) 부착 가능 — 계획도 인물·교과·문서·정체성 축으로 분류.
    #
    # 옵시디언 매핑: 40_Plans/{period}/{date}.md
    # done 토글: 사용자 명시 클릭으로만 (ADR-013).
    #
    # 의존: Domain::Entry (mixin), Domain::ValueObjects::*, Capture::Item (SUBJECTS DRY)
    class Plan
      include Sowing::Domain::Entry

      MODE = :plan

      # period 5종 — daily/weekly/monthly/project/semester
      PERIODS = %i[daily weekly monthly project semester].freeze

      # 4축은 Capture::Item 와 동일 ENUM 재사용 (DRY).
      SUBJECTS = Capture::Item::SUBJECTS

      attr_reader :id, :title, :body, :tags, :template, :subject,
        :period, :plan_date, :done,
        :created_at, :updated_at

      # @param period [Symbol] :daily|:weekly|:monthly|:project|:semester
      # @param plan_date [String] 'YYYY-MM-DD' (daily) / 'YYYY-Www' (weekly) /
      #                            'YYYY-MM' (monthly) / slug (project) / 'YYYY-Sn' (semester)
      # @param done [Boolean] 완료 여부 (사용자 클릭으로만 변경)
      # @param subject [Symbol, nil] :person|:subject|:document|:identity
      def initialize(id:, title:, body:, period:, plan_date:, created_at:,
        tags: Sowing::Domain::ValueObjects::TagSet.new, template: nil, done: false,
        subject: nil, updated_at: nil)
        validate_ulid!(id, :id)
        validate_string!(title, :title)
        validate_string!(body, :body)
        validate_tag_set!(tags)
        validate_optional_string!(template, :template)
        validate_period!(period)
        validate_string!(plan_date, :plan_date)
        validate_optional_subject!(subject)
        validate_time!(created_at, :created_at)
        updated_at ||= created_at
        validate_time!(updated_at, :updated_at)

        @id = id
        @title = title.freeze
        @body = body.freeze
        @tags = tags
        @template = template&.freeze
        @period = period.to_sym
        @plan_date = plan_date.freeze
        @done = !!done
        @subject = subject
        @created_at = created_at
        @updated_at = updated_at
        freeze
      end

      def mode
        MODE
      end

      def to_frontmatter
        common_frontmatter.merge(
          "period" => period.to_s,
          "plan_date" => plan_date,
          "done" => done,
          "subject" => subject&.to_s
        ).compact
      end

      private

      def validate_period!(value)
        return if PERIODS.include?(value.to_sym)
        raise ArgumentError, "Plan period 는 #{PERIODS.inspect} 중 하나여야 합니다: #{value.inspect}"
      end

      def validate_optional_subject!(value)
        return if value.nil?
        return if SUBJECTS.include?(value)
        raise ArgumentError,
          "subject 는 #{SUBJECTS.inspect} 중 하나여야 합니다 (받은 값: #{value.inspect})"
      end
    end
  end
end
