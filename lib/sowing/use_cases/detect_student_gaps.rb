# frozen_string_literal: true

require "dry/monads"
require "time"

module Sowing
  module UseCases
    # 학급 명단 vs 최근 N주 entities 매칭 → 미언급 학생 알림 (W17-T03).
    #
    # **결정적 task** — LLM 미사용. 명단/엔티티 동등 비교만.
    # ROADMAP 검증: 명단 30명 + 엔티티 → 미언급 7명 정확 식별.
    #
    # 사용처:
    #   - 대시보드 카드 ("지난 4주간 한 번도 등장 안 한 학생 N명")
    #   - 학기 회고 (Phase 12 SemesterReflection 의 입력)
    #   - 교사가 의도하지 않은 방치를 조기에 발견
    #
    # 입력:
    #   - class_roster (Settings 또는 인자) — 학생 이름 배열
    #   - weeks_back (기본 4) — 몇 주 전부터 활성으로 간주할지
    #
    # 출력:
    #   - unmentioned: 명단에 있으나 최근 N주 mention 없는 학생들
    #   - mentioned: 최근 N주 mention 있는 학생들
    #   - roster_size, mentioned_count, gap_ratio (0.0~1.0)
    class DetectStudentGaps
      include Dry::Monads[:result]

      DEFAULT_WEEKS_BACK = 4

      def initialize(db: nil, clock: Time)
        @db = db || Core::DB.connection
        @clock = clock
      end

      # @param class_roster [Array<String>, nil] 학생 이름. nil 이면 Settings 에서 로드.
      # @param weeks_back [Integer] 활성 기준 (주). 기본 4.
      # @return [Result] Success({unmentioned, mentioned, roster_size, mentioned_count,
      #                           gap_ratio, since, weeks_back})
      #         Failure(:empty_roster) 명단 빈 경우
      def call(class_roster: nil, weeks_back: DEFAULT_WEEKS_BACK)
        roster = (class_roster || Core::Settings.load["class_roster"] || []).map { |n| n.to_s.strip }.reject(&:empty?)
        return Failure(:empty_roster) if roster.empty?

        cutoff = @clock.now - (weeks_back * 7 * 24 * 60 * 60)
        cutoff_iso = cutoff.iso8601

        # 최근 N주 안에 last_seen_at 이 있는 학생 entities (활성)
        active_names = @db[:entities]
          .where(type: "student")
          .where { last_seen_at >= cutoff_iso }
          .select_map(:name)
          .to_set

        # 명단 ∩ active = mentioned, 명단 - active = unmentioned (방치 의심)
        roster_set = roster.uniq.to_set
        mentioned = roster.uniq.select { |name| active_names.include?(name) }
        unmentioned = roster.uniq.reject { |name| active_names.include?(name) }

        gap_ratio = roster_set.size.zero? ? 0.0 : (unmentioned.size.to_f / roster_set.size).round(3)

        Success({
          unmentioned: unmentioned,
          mentioned: mentioned,
          roster_size: roster_set.size,
          mentioned_count: mentioned.size,
          unmentioned_count: unmentioned.size,
          gap_ratio: gap_ratio,
          since: cutoff_iso,
          weeks_back: weeks_back
        })
      end
    end
  end
end
