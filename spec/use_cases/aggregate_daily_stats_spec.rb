# frozen_string_literal: true

RSpec.describe Sowing::UseCases::AggregateDailyStats do
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 5, 8, 14, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  let(:use_case) { described_class.new(db: db, clock: clock) }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    db[:daily_stats].delete
  end

  def insert_entry(id:, mode:, created_at:, path: "00_Inbox/#{id}.md")
    db[:entries].insert(
      id: id, path: path, mode: mode, title: nil,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: 1, indexed_at: created_at
    )
  end

  describe "#call — 기본 집계" do
    it "빈 entries → 0 rows 갱신" do
      result = use_case.call
      expect(result).to be_success
      expect(result.value!).to eq(0)
      expect(db[:daily_stats].count).to eq(0)
    end

    it "같은 날 메모 3건 → memos_count=3, total=3" do
      3.times do |i|
        insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA#{i}", mode: "memo",
          created_at: format("2026-05-08T%02d:00:00+09:00", 9 + i))
      end
      use_case.call

      row = db[:daily_stats].where(date: "2026-05-08").first
      expect(row[:memos_count]).to eq(3)
      expect(row[:total_count]).to eq(3)
    end

    it "같은 날 모드 혼합 → 컬럼별 분리" do
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA0", mode: "memo", created_at: "2026-05-08T09:00:00+09:00")
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA1", mode: "note", created_at: "2026-05-08T10:00:00+09:00")
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA2", mode: "note", created_at: "2026-05-08T11:00:00+09:00")
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA3", mode: "record", created_at: "2026-05-08T12:00:00+09:00")
      use_case.call

      row = db[:daily_stats].where(date: "2026-05-08").first
      expect(row[:memos_count]).to eq(1)
      expect(row[:notes_count]).to eq(2)
      expect(row[:records_count]).to eq(1)
      expect(row[:total_count]).to eq(4)
    end

    it "여러 날짜 → row 분리" do
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA0", mode: "memo", created_at: "2026-05-06T09:00:00+09:00")
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA1", mode: "memo", created_at: "2026-05-07T09:00:00+09:00")
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA2", mode: "memo", created_at: "2026-05-08T09:00:00+09:00")
      use_case.call

      expect(db[:daily_stats].count).to eq(3)
    end

    it "computed_at은 clock.now (iso8601)" do
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA0", mode: "memo", created_at: "2026-05-08T09:00:00+09:00")
      use_case.call
      row = db[:daily_stats].first
      expect(row[:computed_at]).to eq(fixed_now.iso8601)
    end
  end

  describe "멱등성" do
    it "두 번 호출해도 같은 결과 (전체 비우고 재계산)" do
      2.times do |i|
        insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA#{i}", mode: "memo",
          created_at: format("2026-05-08T%02d:00:00+09:00", 9 + i))
      end
      use_case.call
      first_row = db[:daily_stats].where(date: "2026-05-08").first.dup

      use_case.call
      second_row = db[:daily_stats].where(date: "2026-05-08").first

      expect(first_row).to eq(second_row)
    end

    it "entry 삭제 후 재집계 → 사라진 날 row 제거" do
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA0", mode: "memo", created_at: "2026-05-07T09:00:00+09:00")
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA1", mode: "memo", created_at: "2026-05-08T09:00:00+09:00")
      use_case.call
      expect(db[:daily_stats].count).to eq(2)

      db[:entries].where(id: "01KR1AAAAAAAAAAAAAAAAAAAA0").delete
      use_case.call
      expect(db[:daily_stats].count).to eq(1)
      expect(db[:daily_stats].first[:date]).to eq("2026-05-08")
    end
  end

  describe "시간대 (KST 고정)" do
    it "UTC 기준 자정 직전(23:30 UTC = 익일 08:30 KST)은 KST 익일로" do
      # 2026-05-07T23:30:00Z = 2026-05-08T08:30:00+09:00
      insert_entry(id: "01KR1AAAAAAAAAAAAAAAAAAAA0", mode: "memo", created_at: "2026-05-07T23:30:00Z")
      use_case.call
      expect(db[:daily_stats].first[:date]).to eq("2026-05-08")
    end
  end
end
