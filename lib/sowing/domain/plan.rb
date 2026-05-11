# frozen_string_literal: true

module Sowing
  module Domain
    # 계획 (Plan): 미래에 할 글·일·작업의 청사진.
    # 옵시디언 매핑: 40_Plans/{period}/{date}.md
    #
    # Phase 13 W27-T01 — '쓸 글 계획' 4번째 1급 mode. ADR-014 (동사 중심 IA)
    # 의 핵심 구현. 기존 Memo·Note·Record 가 회상 단위라면, Plan 은 실행 단위.
    #
    # period 3종 (PoC):
    #   - daily   : 하루 단위 todo (오늘 할 일)
    #   - weekly  : 일주일 단위 계획
    #   - monthly : 한 달 로드맵
    # 후속 T02: project (장기), semester (분기) 추가 예정.
    #
    # done 토글: 사용자 명시 클릭으로만 (ADR-013) — 자동 완료 처리 없음.
    class Plan
      include Entry

      MODE = :plan

      PERIODS = %i[daily weekly monthly].freeze

      attr_reader :id, :title, :body, :tags, :template,
        :period, :plan_date, :done,
        :created_at, :updated_at

      # @param period [Symbol] :daily|:weekly|:monthly
      # @param plan_date [String] 'YYYY-MM-DD' (daily), 'YYYY-Www' (weekly),
      #                            'YYYY-MM' (monthly). 외부 표현 그대로 보존.
      # @param done [Boolean] 완료 여부
      def initialize(id:, title:, body:, period:, plan_date:, created_at:,
        tags: ValueObjects::TagSet.new, template: nil, done: false,
        updated_at: nil)
        validate_ulid!(id, :id)
        validate_string!(title, :title)
        validate_string!(body, :body)
        validate_tag_set!(tags)
        validate_optional_string!(template, :template)
        validate_period!(period)
        validate_string!(plan_date, :plan_date)
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
          "done" => done
        ).compact
      end

      private

      def validate_period!(value)
        return if PERIODS.include?(value.to_sym)
        raise ArgumentError, "Plan period 는 #{PERIODS.inspect} 중 하나여야 합니다: #{value.inspect}"
      end
    end
  end
end
