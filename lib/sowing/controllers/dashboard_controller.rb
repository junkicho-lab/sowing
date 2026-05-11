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

        # Phase 13 W28-T03 — daily_mirror_enabled 켜져 있으면 자동으로 오늘 거울 생성.
        # 결과는 .sowing/synth/self-mirror/ 검토 대기 (ADR-013 — 정식 기록 X).
        # 통계 재집계 직후 호출 — 'entries 수 ≥ 3' 판정에 최신 데이터 반영.
        maybe_auto_generate_mirror
        @recent_memos = recent_memos
        @today_stats = stats_repo.today
        @week_count = stats_repo.this_week
        @month_count = stats_repo.this_month
        @streak = stats_repo.current_streak
        @growth = Domain::ValueObjects::GrowthStage.new(stats_repo.total_all_time)
        @tutorial_completed = !Infrastructure::Settings.load["tutorial_completed_at"].nil?
        @gap_summary = compute_gap_summary
        @on_this_day = compute_on_this_day  # 30년 시나리오 — 같은 월·일 다년 entries
        @synth_summary = compute_synth_summary  # 16 합성기 검토 대기 카운트
        @todays_plans = compute_todays_plans   # W27-T02: 오늘 할 일 위젯 (미완료 daily)
        @todays_mirror = compute_todays_mirror # W28-T02: 자기 거울 카드 (있으면 요약, 없으면 생성 버튼)
        erb :"dashboard/show", layout: :"layouts/application"
      end

      private

      # 16 type 합성기 검토 대기 카운트 + 가장 최근 합성 안내.
      # 16 type 모든 디렉토리를 한 번에 스캔 — vault 가 작아 비용 미미.
      # SynthController::SYNTH_TYPES 와 동기화 (controller 가 source of truth).
      def compute_synth_summary
        synth_root = Infrastructure::Paths.vault_dir.join(".sowing/synth")
        return nil unless synth_root.exist?

        types_meta = Sowing::Controllers::SynthController::SYNTH_TYPES
        items = []
        types_meta.each do |type, meta|
          dir = synth_root.join(meta[:subdir])
          next unless dir.exist?
          paths = Dir.glob(dir.join("*.md"))
          next if paths.empty?
          items << {type: type, label: meta[:label], icon: meta[:icon], count: paths.size}
        end
        return nil if items.empty?

        # 가장 최근 합성 1건 — 모든 type 의 모든 파일 mtime 으로 정렬
        all_paths = Dir.glob(synth_root.join("*", "*.md"))
        latest = all_paths.max_by { |p| File.mtime(p) }
        latest_info = nil
        if latest
          rel = latest.delete_prefix(synth_root.to_s + "/")
          latest_info = {path: rel, mtime: File.mtime(latest)}
        end

        {types: items, total: items.sum { |i| i[:count] }, latest: latest_info}
      end

      # "이날의 회고" — 오늘과 같은 월·일의 과거 연도 entries.
      # 매일 자연스럽게 30년 환기. 의식적 검색 0.
      def compute_on_this_day(limit: 5)
        today = Time.now
        rows = index_repo.on_this_day(month: today.month, day: today.day,
          exclude_year: today.year, limit: limit)
        return nil if rows.empty?
        rows.map { |entry|
          year = Time.parse(entry.created_at.to_s).year
          {entry: entry, year: year, years_ago: today.year - year}
        }
      end

      # 학급 명단이 설정돼 있으면 미언급 학생 알림 (W17-T03 GapDetector).
      # 명단 없으면 nil — 카드 표시 안 함.
      def compute_gap_summary
        roster = Infrastructure::Settings.load["class_roster"]
        return nil if roster.nil? || roster.empty?
        UseCases::DetectStudentGaps.new.call.value_or(nil)
      end

      # Phase 13 W28-T03 — 자동 생성 hook.
      # 조건 (모두 만족):
      #   - daily_mirror_enabled == true (사용자 opt-in)
      #   - 오늘 mirror 파일 없음
      #   - 오늘 entries ≥ MIN_ENTRIES (3) — SelfMirror use case 가 보호
      # 자동 호출도 audit log 에는 actor=agent 로 표시.
      # 결과는 .sowing/synth/ 검토 대기 — 사용자 수락 클릭 없이는 정식 기록 안 됨 (ADR-013).
      def maybe_auto_generate_mirror
        return unless Infrastructure::Settings.load["daily_mirror_enabled"] == true
        today_str = Time.now.strftime("%Y-%m-%d")
        mirror_path = Infrastructure::Paths.vault_dir
          .join(".sowing/synth/self-mirror/daily-#{today_str}.md")
        return if mirror_path.exist?

        # entries 수 사전 체크 — use case 가 또 검증하지만 불필요한 호출 피함
        today_start = Time.parse("#{today_str}T00:00:00")
        today_end = Time.parse("#{today_str}T23:59:59")
        count = Infrastructure::DB.connection[:entries]
          .where { (created_at >= today_start.iso8601) & (created_at <= today_end.iso8601) }
          .count
        return if count < UseCases::SynthesizeSelfMirror::MIN_ENTRIES

        Infrastructure::AuditLog.with_actor("agent") do
          UseCases::SynthesizeSelfMirror.new.call(period: :daily, date: today_str)
        end
      rescue
        # 자동 생성 실패해도 dashboard 부팅 막지 않음
        nil
      end

      # Phase 13 W28-T02 — 오늘의 자기 거울 위젯.
      # 상태 3종:
      #   :ready    — 오늘 self-mirror 파일 존재. frontmatter + 5축 요약 표시.
      #   :prompt   — 파일 없음 + 옵션 켜짐 + 오늘 entries ≥ 3 → '생성하기' 버튼.
      #   nil       — 옵션 꺼짐 또는 entries 부족 — 위젯 안 표시.
      def compute_todays_mirror
        return nil unless Infrastructure::Settings.load["daily_mirror_enabled"] == true
        today_str = Time.now.strftime("%Y-%m-%d")
        mirror_path = Infrastructure::Paths.vault_dir.join(".sowing/synth/self-mirror/daily-#{today_str}.md")

        if mirror_path.exist?
          fm = FrontMatterParser::Parser.new(:md).call(File.read(mirror_path))&.front_matter
          return {
            status: :ready,
            date: today_str,
            slug: "daily-#{today_str}",
            positive_count: fm["synth_positive_count"],
            negative_count: fm["synth_negative_count"],
            source_count: fm["synth_source_count"],
            relation_count: fm["synth_relation_count"],
            model: fm["synth_model"]
          }
        end

        # 미생성 — 오늘 entries 가 MIN_ENTRIES(3) 이상이면 생성 prompt
        today_t_start = Time.parse("#{today_str}T00:00:00")
        today_t_end = Time.parse("#{today_str}T23:59:59")
        count = Infrastructure::DB.connection[:entries]
          .where { (created_at >= today_t_start.iso8601) & (created_at <= today_t_end.iso8601) }
          .count
        return nil if count < 3
        {status: :prompt, date: today_str, today_count: count}
      rescue
        nil  # graceful — Plan/Mirror 인프라 부재 또는 깨진 frontmatter 시 위젯 안 표시
      end

      # Phase 13 W27-T02 — 오늘 할 일 위젯.
      # 오늘 날짜 (YYYY-MM-DD) 의 daily plan 중 미완료 항목만.
      # 없으면 nil 반환 → 위젯 안 표시.
      def compute_todays_plans
        plan_repo = Repositories::PlanRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        today_str = Date.today.strftime("%Y-%m-%d")
        pending = plan_repo
          .list_by_period(:daily)
          .select { |p| p.plan_date == today_str && !p.done }
        return nil if pending.empty?
        {
          date: today_str,
          plans: pending,
          count: pending.size
        }
      rescue # graceful — Plan 인프라 부재 시 대시보드 부팅 막지 않음
        nil
      end
    end
  end
end
