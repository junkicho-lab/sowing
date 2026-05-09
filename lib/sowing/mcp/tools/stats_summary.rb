# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 대시보드 통계 + GrowthStage 요약. StatsRepo + GrowthStage 활용.
      # 외부 에이전트가 "이번 주 통계" 같은 자연어 요청 시 호출.
      class StatsSummary < Base
        tool_name "stats_summary"
        description "오늘/이번주(7일)/이번달 카운트 + streak + 누적 + 성장 단계. AggregateDailyStats 자동 갱신 후 반환."
        input_schema(properties: {})

        def self.call(server_context: nil)
          # 진입마다 재집계 — 최신값 보장 (DashboardController 와 동일 정책).
          UseCases::AggregateDailyStats.new.call

          stats = Repositories::StatsRepo.new
          today = stats.today
          growth = Domain::ValueObjects::GrowthStage.new(stats.total_all_time)

          json_response({
            today: {
              date: today.date,
              total: today.total_count,
              memos: today.memos_count,
              notes: today.notes_count,
              records: today.records_count
            },
            this_week: stats.this_week,
            this_month: stats.this_month,
            streak_days: stats.current_streak,
            total_all_time: stats.total_all_time,
            growth: {
              stage: growth.key.to_s,
              label: growth.label,
              message: growth.message,
              next_threshold: growth.next_threshold,
              remaining_to_next: growth.remaining_to_next,
              progress_ratio: growth.progress_ratio.round(3)
            }
          })
        end
      end
    end
  end
end
