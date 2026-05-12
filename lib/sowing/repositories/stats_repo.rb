# frozen_string_literal: true

require "date"
require "time"

module Sowing
  module Repositories
    # daily_stats 조회 어댑터 (W6-T01/T02).
    #
    # 모든 메서드는 KST 기준. clock + tz_offset 주입 가능 — 테스트에서 시점 고정.
    # 비어있는 날은 0으로 자동 채움 (today/this_week/this_month는 daily_stats row가 없어도 0 반환).
    class StatsRepo
      Daily = Data.define(:date, :memos_count, :notes_count, :records_count, :total_count)

      def initialize(db: Core::DB.connection, clock: Time, tz_offset: "+09:00")
        @db = db
        @clock = clock
        @tz_offset = tz_offset
      end

      # @return [Daily] 오늘(KST) 통계 — row 없으면 0으로 채움
      def today
        for_date(today_date)
      end

      # 최근 7일 합계 (오늘 포함, 어제까지 6일).
      def this_week
        range_total(today_date - 6, today_date)
      end

      # 이번 달 1일부터 오늘까지 합계.
      def this_month
        first = Date.new(today_date.year, today_date.month, 1)
        range_total(first, today_date)
      end

      # 연속 작성일 — 오늘(KST)부터 거꾸로, total_count > 0인 날을 셈. 빈 날에서 종료.
      # 오늘이 비어 있으면 streak = 0.
      # @return [Integer]
      def current_streak
        streak = 0
        cursor = today_date
        loop do
          stat = @db[:daily_stats].where(date: cursor.to_s).first
          break if stat.nil? || stat[:total_count].to_i <= 0
          streak += 1
          cursor -= 1
        end
        streak
      end

      # 누적 전체 entry 수 (씨앗-숲 시각화의 입력값, W6-T03).
      def total_all_time
        @db[:daily_stats].sum(:total_count).to_i
      end

      # @param date [Date]
      # @return [Daily]
      def for_date(date)
        row = @db[:daily_stats].where(date: date.to_s).first
        if row
          Daily.new(
            date: date.to_s,
            memos_count: row[:memos_count].to_i,
            notes_count: row[:notes_count].to_i,
            records_count: row[:records_count].to_i,
            total_count: row[:total_count].to_i
          )
        else
          empty(date)
        end
      end

      private

      def today_date
        @clock.now.getlocal(@tz_offset).to_date
      end

      def range_total(start, finish)
        @db[:daily_stats].where(date: start.to_s..finish.to_s).sum(:total_count).to_i
      end

      def empty(date)
        Daily.new(date: date.to_s, memos_count: 0, notes_count: 0, records_count: 0, total_count: 0)
      end
    end
  end
end
