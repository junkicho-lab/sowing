# frozen_string_literal: true

module Sowing
  module Controllers
    # 대시보드(홈). 사용자가 진입하는 첫 화면.
    # SPEC §10.3 와이어프레임 참조.
    class DashboardController < ApplicationController
      RECENT_LIMIT = 5

      helpers do
        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        end

        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        def stats_repo
          @stats_repo ||= Repositories::StatsRepo.new
        end

        def aggregate_stats_use_case
          UseCases::AggregateDailyStats.new
        end

        # 최근 메모 N건. 인덱스로 빠르게 정렬·페이징, body는 마크다운 파일에서 로드.
        # 파일이 누락된 인덱스 row는 건너뜀 (정합성 깨진 경우 graceful).
        def recent_memos(limit: RECENT_LIMIT)
          index_repo.list(mode: :memo).first(limit).filter_map do |indexed|
            vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            nil
          end
        end
      end

      get "/" do
        @page_title = "대시보드"
        # 페이지 진입마다 통계 재집계 — 적은 데이터(수만 건 미만)에서 충분히 빠르고,
        # 별도 cron·SSE 없이도 항상 최신값 보장. 비용 커지면 W7+ 백그라운드 잡으로 이전.
        aggregate_stats_use_case.call
        @recent_memos = recent_memos
        @today_stats = stats_repo.today
        @week_count = stats_repo.this_week
        @month_count = stats_repo.this_month
        @streak = stats_repo.current_streak
        @growth = Domain::ValueObjects::GrowthStage.new(stats_repo.total_all_time)
        @tutorial_completed = !Infrastructure::Settings.load["tutorial_completed_at"].nil?
        @gap_summary = compute_gap_summary
        erb :"dashboard/show", layout: :"layouts/application"
      end

      private

      # 학급 명단이 설정돼 있으면 미언급 학생 알림 (W17-T03 GapDetector).
      # 명단 없으면 nil — 카드 표시 안 함.
      def compute_gap_summary
        roster = Infrastructure::Settings.load["class_roster"]
        return nil if roster.nil? || roster.empty?
        UseCases::DetectStudentGaps.new.call.value_or(nil)
      end
    end
  end
end
