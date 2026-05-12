# frozen_string_literal: true

require "date"

RSpec.describe Sowing::Repositories::StatsRepo do
  let(:db) { Sowing::Core::DB.connection }
  # 2026-05-08 (Fri) 14:00 KST 고정.
  let(:fixed_now) { Time.new(2026, 5, 8, 14, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  let(:repo) { described_class.new(db: db, clock: clock) }

  before do
    db[:daily_stats].delete
  end

  def insert_stat(date:, memos: 0, notes: 0, records: 0)
    db[:daily_stats].insert(
      date: date, memos_count: memos, notes_count: notes,
      records_count: records, total_count: memos + notes + records,
      computed_at: fixed_now.iso8601
    )
  end

  describe "#today" do
    it "오늘 stats — row 있으면 그대로 반환" do
      insert_stat(date: "2026-05-08", memos: 2, notes: 1)
      today = repo.today
      expect(today.date).to eq("2026-05-08")
      expect(today.memos_count).to eq(2)
      expect(today.notes_count).to eq(1)
      expect(today.total_count).to eq(3)
    end

    it "오늘 row 없으면 0으로 채움" do
      today = repo.today
      expect(today.total_count).to eq(0)
      expect(today.memos_count).to eq(0)
    end
  end

  describe "#this_week (지난 7일 — 오늘 포함)" do
    it "지난 7일 합계, 8일 전은 제외" do
      insert_stat(date: "2026-05-08", memos: 1) # today
      insert_stat(date: "2026-05-07", memos: 1)
      insert_stat(date: "2026-05-02", memos: 1) # 7일 전 (포함 — today - 6 = 5/2)
      insert_stat(date: "2026-05-01", memos: 1) # 8일 전 — 제외

      expect(repo.this_week).to eq(3)
    end
  end

  describe "#this_month" do
    it "이번 달 1일 ~ 오늘" do
      insert_stat(date: "2026-05-01", memos: 5)
      insert_stat(date: "2026-05-08", memos: 2)
      insert_stat(date: "2026-04-30", memos: 99) # 지난달 — 제외

      expect(repo.this_month).to eq(7)
    end
  end

  describe "#current_streak" do
    it "오늘 0건이면 streak = 0" do
      insert_stat(date: "2026-05-07", memos: 1)
      expect(repo.current_streak).to eq(0)
    end

    it "오늘부터 7일 연속 작성 → streak = 7" do
      7.times do |i|
        insert_stat(date: (Date.new(2026, 5, 8) - i).to_s, memos: 1)
      end
      expect(repo.current_streak).to eq(7)
    end

    it "중간에 빈 날 있으면 거기서 종료 (오늘부터의 연속만)" do
      insert_stat(date: "2026-05-08", memos: 1)
      insert_stat(date: "2026-05-07", memos: 1)
      # 5-6 빈 날
      insert_stat(date: "2026-05-05", memos: 1)
      expect(repo.current_streak).to eq(2)
    end

    it "오늘만 있고 어제 없으면 streak = 1" do
      insert_stat(date: "2026-05-08", memos: 1)
      expect(repo.current_streak).to eq(1)
    end
  end

  describe "#for_date" do
    it "임의 날짜 조회 — row 있으면 반환" do
      insert_stat(date: "2026-05-01", memos: 3)
      stat = repo.for_date(Date.new(2026, 5, 1))
      expect(stat.memos_count).to eq(3)
    end

    it "row 없으면 0으로 채워서 반환" do
      stat = repo.for_date(Date.new(2026, 5, 1))
      expect(stat.total_count).to eq(0)
    end
  end
end
