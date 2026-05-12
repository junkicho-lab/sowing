# frozen_string_literal: true

# 30년 시나리오 — IndexRepo 의 cross-year 쿼리 (on_this_day / list_records_flat /
# category_year_matrix). 폴더 구조 무관 시간 무관 탐색.

RSpec.describe Sowing::Repositories::IndexRepo, "cross-year (30년 시나리오)" do
  let(:db) { Sowing::Core::DB.connection }
  let(:repo) { described_class.new }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  def make_record(title:, created_at:, body: "본문", category: "수업회고")
    Sowing::Domain::Record.new(
      id: Sowing::Domain::ValueObjects::Ulid.generate,
      title: title,
      body: body,
      category: category,
      created_at: Time.parse(created_at)
    )
  end

  def upsert(entry)
    rel_path = case entry.mode
    when :record then "30_Records/#{entry.created_at.year}/#{entry.category}/#{entry.id}.md"
    when :note then "20_Notes/#{entry.category}/#{entry.id}.md"
    when :memo then "00_Inbox/#{entry.id}.md"
    end
    repo.upsert(entry, path: rel_path, file_mtime: 0, file_hash: "0" * 16, word_count: 1)
  end

  describe "#on_this_day" do
    it "같은 월·일의 다른 연도 entries 만 (exclude_year 적용)" do
      upsert(make_record(title: "2024-05-11", created_at: "2024-05-11T09:00:00+09:00"))
      upsert(make_record(title: "2025-05-11", created_at: "2025-05-11T09:00:00+09:00"))
      upsert(make_record(title: "2026-05-11", created_at: "2026-05-11T09:00:00+09:00"))
      upsert(make_record(title: "2025-05-12", created_at: "2025-05-12T09:00:00+09:00"))  # 다른 날

      result = repo.on_this_day(month: 5, day: 11, exclude_year: 2026)
      titles = result.map(&:title)
      expect(titles).to include("2025-05-11", "2024-05-11")
      expect(titles).not_to include("2026-05-11")  # exclude_year
      expect(titles).not_to include("2025-05-12")  # 다른 날
    end

    it "exclude_year nil — 모든 연도 포함" do
      upsert(make_record(title: "T1", created_at: "2024-03-15T09:00:00+09:00"))
      upsert(make_record(title: "T2", created_at: "2026-03-15T09:00:00+09:00"))

      result = repo.on_this_day(month: 3, day: 15)
      expect(result.size).to eq(2)
    end

    it "limit 적용 (default 5)" do
      6.times do |i|
        upsert(make_record(title: "y#{2020 + i}", created_at: "#{2020 + i}-04-01T09:00:00+09:00"))
      end
      expect(repo.on_this_day(month: 4, day: 1).size).to eq(5)
      expect(repo.on_this_day(month: 4, day: 1, limit: 10).size).to eq(6)
    end

    it "최근 연도 내림차순" do
      upsert(make_record(title: "old", created_at: "2020-06-01T09:00:00+09:00"))
      upsert(make_record(title: "new", created_at: "2024-06-01T09:00:00+09:00"))
      upsert(make_record(title: "mid", created_at: "2022-06-01T09:00:00+09:00"))

      titles = repo.on_this_day(month: 6, day: 1).map(&:title)
      expect(titles).to eq(%w[new mid old])
    end

    it "결과 0건 빈 배열 — Failure 반환 안 함 (use case 가 처리)" do
      expect(repo.on_this_day(month: 12, day: 31)).to eq([])
    end
  end

  describe "#list_records_flat" do
    before do
      upsert(make_record(title: "수업1", category: "수업회고", created_at: "2024-03-10T09:00:00+09:00"))
      upsert(make_record(title: "수업2", category: "수업회고", created_at: "2025-04-15T09:00:00+09:00"))
      upsert(make_record(title: "상담1", category: "상담", created_at: "2024-05-20T09:00:00+09:00"))
      upsert(make_record(title: "평가1", category: "평가", created_at: "2026-06-25T09:00:00+09:00"))
    end

    it "시간순 내림차순 (default desc)" do
      result = repo.list_records_flat
      titles = result.map(&:title)
      expect(titles).to eq(%w[평가1 수업2 상담1 수업1])
    end

    it "오름차순 옵션" do
      result = repo.list_records_flat(order: :asc)
      expect(result.map(&:title)).to eq(%w[수업1 상담1 수업2 평가1])
    end

    it "다중 카테고리 필터 (category_in)" do
      result = repo.list_records_flat(category_in: %w[수업회고 평가])
      titles = result.map(&:title)
      expect(titles).to include("수업1", "수업2", "평가1")
      expect(titles).not_to include("상담1")
    end

    it "since/until 날짜 범위" do
      result = repo.list_records_flat(
        since: Time.parse("2025-01-01T00:00:00+09:00"),
        until_time: Time.parse("2025-12-31T23:59:59+09:00")
      )
      expect(result.map(&:title)).to eq(["수업2"])
    end

    it "30년 cross-year 동시 필터 — 카테고리 + 날짜 범위 결합" do
      result = repo.list_records_flat(
        category_in: ["수업회고"],
        since: Time.parse("2024-01-01T00:00:00+09:00"),
        until_time: Time.parse("2025-12-31T23:59:59+09:00")
      )
      titles = result.map(&:title)
      expect(titles.sort).to eq(%w[수업1 수업2])
    end

    it "limit/offset 페이지네이션" do
      page1 = repo.list_records_flat(limit: 2, offset: 0)
      page2 = repo.list_records_flat(limit: 2, offset: 2)
      expect(page1.map(&:title)).to eq(%w[평가1 수업2])
      expect(page2.map(&:title)).to eq(%w[상담1 수업1])
    end
  end

  describe "#count_records_flat" do
    it "list_records_flat 와 같은 필터로 카운트" do
      upsert(make_record(title: "a", category: "수업회고", created_at: "2024-03-10T09:00:00+09:00"))
      upsert(make_record(title: "b", category: "수업회고", created_at: "2025-04-15T09:00:00+09:00"))
      upsert(make_record(title: "c", category: "상담", created_at: "2024-05-20T09:00:00+09:00"))

      expect(repo.count_records_flat).to eq(3)
      expect(repo.count_records_flat(category_in: ["수업회고"])).to eq(2)
      expect(repo.count_records_flat(
        since: Time.parse("2025-01-01T00:00:00+09:00")
      )).to eq(1)
    end
  end

  describe "#category_year_matrix" do
    before do
      upsert(make_record(title: "a1", category: "수업회고", created_at: "2024-03-10T09:00:00+09:00"))
      upsert(make_record(title: "a2", category: "수업회고", created_at: "2024-04-15T09:00:00+09:00"))
      upsert(make_record(title: "a3", category: "수업회고", created_at: "2025-05-20T09:00:00+09:00"))
      upsert(make_record(title: "b1", category: "상담", created_at: "2024-06-01T09:00:00+09:00"))
      upsert(make_record(title: "b2", category: "상담", created_at: "2026-07-01T09:00:00+09:00"))
    end

    it "category × year 카운트 정확" do
      m = repo.category_year_matrix(mode: "record")
      expect(m["수업회고"][2024]).to eq(2)
      expect(m["수업회고"][2025]).to eq(1)
      expect(m["수업회고"][2026]).to be_nil
      expect(m["상담"][2024]).to eq(1)
      expect(m["상담"][2026]).to eq(1)
    end

    it "카테고리 nil/빈 entry 제외" do
      # category 가 nil 인 entry 시드 — 매트릭스에서 제외
      Sowing::Core::DB.connection[:entries].insert(
        id: "01NULL0000000000000000A1", mode: "record", path: "30_Records/2024/null.md",
        category: nil, title: "null cat",
        created_at: "2024-08-01T09:00:00+09:00", updated_at: "2024-08-01T09:00:00+09:00",
        file_mtime: 0, file_hash: "0" * 16, word_count: 1, indexed_at: "2024-08-01T09:00:00+09:00"
      )

      m = repo.category_year_matrix(mode: "record")
      expect(m).not_to have_key(nil)
      expect(m).not_to have_key("")
    end
  end
end
