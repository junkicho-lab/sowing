# frozen_string_literal: true

require "dry/monads"
require "time"

module Sowing
  module UseCases
    # entries → daily_stats 재집계 (W6-T01).
    #
    # 트랜잭션으로 daily_stats 전체 비우고 재계산 — 멱등하며 race-free.
    # 부팅 시 또는 야간 cron에서 호출. 작은 데이터(수만 건 미만)에서는 충분히 빠르다.
    #
    # 시간대: KST 고정. created_at은 iso8601 with offset이므로 getlocal로 KST date 추출.
    class AggregateDailyStats
      include Dry::Monads[:result]

      MODE_TO_COL = {
        "memo" => :memos_count,
        "note" => :notes_count,
        "record" => :records_count
      }.freeze

      def initialize(db: Core::DB.connection, clock: Time, tz_offset: "+09:00")
        @db = db
        @clock = clock
        @tz_offset = tz_offset
      end

      # @return [Success(Integer)] 갱신된 daily_stats row 수
      def call
        @db.transaction do
          @db[:daily_stats].delete
          rows = aggregate_rows
          @db[:daily_stats].multi_insert(rows) unless rows.empty?
          Success(rows.size)
        end
      end

      private

      def aggregate_rows
        buckets = Hash.new { |h, k| h[k] = {memos_count: 0, notes_count: 0, records_count: 0} }
        @db[:entries].select(:mode, :created_at).each do |row|
          date = Time.iso8601(row[:created_at]).getlocal(@tz_offset).strftime("%Y-%m-%d")
          col = MODE_TO_COL[row[:mode]]
          buckets[date][col] += 1 if col
        end

        now = @clock.now.iso8601
        buckets.map do |date, counts|
          {
            date: date,
            memos_count: counts[:memos_count],
            notes_count: counts[:notes_count],
            records_count: counts[:records_count],
            total_count: counts.values.sum,
            computed_at: now
          }
        end
      end
    end
  end
end
