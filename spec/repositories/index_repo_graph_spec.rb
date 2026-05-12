# frozen_string_literal: true

# 30년 시나리오 #4 — IndexRepo#graph_data (위키링크 그래프).

RSpec.describe Sowing::Repositories::IndexRepo, "#graph_data (그래프 시각화)" do
  let(:db) { Sowing::Core::DB.connection }
  let(:repo) { described_class.new }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  def make_record(title:, created_at:, category: "수업회고")
    Sowing::Domain::Record.new(
      id: Sowing::Domain::ValueObjects::Ulid.generate,
      title: title,
      body: "본문 #{title}",
      category: category,
      created_at: Time.parse(created_at)
    )
  end

  def upsert(entry, mode_override: nil)
    rel_path = case (mode_override || entry.mode).to_sym
    when :record then "30_Records/#{entry.created_at.year}/#{entry.category}/#{entry.id}.md"
    when :note then "20_Notes/#{entry.category || "lessons"}/#{entry.id}.md"
    when :memo then "00_Inbox/#{entry.id}.md"
    end
    repo.upsert(entry, path: rel_path, file_mtime: 0, file_hash: "0" * 16, word_count: 1)
  end

  def link(source, target)
    db[:links].insert(
      source_id: source.id.to_s,
      target_id: target.id.to_s,
      target_text: target.title.to_s
    )
  end

  describe "기본 동작" do
    it "노드 + 엣지 + 카운트 반환" do
      a = make_record(title: "A", created_at: "2024-01-01T09:00:00+09:00")
      b = make_record(title: "B", created_at: "2024-02-01T09:00:00+09:00")
      c = make_record(title: "C", created_at: "2025-03-01T09:00:00+09:00")
      [a, b, c].each { |e| upsert(e) }
      link(a, b)
      link(a, c)
      link(b, c)

      data = repo.graph_data
      expect(data[:nodes].size).to eq(3)
      expect(data[:edges].size).to eq(3)
      expect(data[:truncated]).to be false
      expect(data[:total]).to eq(3)
    end

    it "노드 메타 — id/mode/title/category/year/inbound/outbound" do
      a = make_record(title: "A", created_at: "2024-01-01T09:00:00+09:00", category: "수업회고")
      b = make_record(title: "B", created_at: "2025-02-01T09:00:00+09:00", category: "상담")
      c = make_record(title: "C", created_at: "2024-06-01T09:00:00+09:00", category: "수업회고")
      [a, b, c].each { |e| upsert(e) }
      link(a, b)  # a→b (outbound=1 for a, inbound=1 for b)
      link(c, b)  # c→b (inbound=2 for b)

      data = repo.graph_data
      a_node = data[:nodes].find { |n| n[:title] == "A" }
      b_node = data[:nodes].find { |n| n[:title] == "B" }

      expect(a_node[:mode]).to eq("record")
      expect(a_node[:category]).to eq("수업회고")
      expect(a_node[:year]).to eq(2024)
      expect(a_node[:outbound]).to eq(1)
      expect(a_node[:inbound]).to eq(0)

      expect(b_node[:year]).to eq(2025)
      expect(b_node[:inbound]).to eq(2)  # a→b + c→b
      expect(b_node[:outbound]).to eq(0)
    end

    it "broken link (target_id NULL) 는 엣지에서 제외" do
      a = make_record(title: "A", created_at: "2024-01-01T09:00:00+09:00")
      upsert(a)
      db[:links].insert(source_id: a.id.to_s, target_id: nil, target_text: "없는링크")

      data = repo.graph_data
      expect(data[:edges]).to be_empty
      a_node = data[:nodes].first
      expect(a_node[:outbound]).to eq(0)  # broken link 는 outbound 카운트 안 함
    end

    it "filter 안에서의 internal links 만 엣지 (외부 노드 가는 엣지 제외)" do
      a = make_record(title: "A", created_at: "2024-01-01T09:00:00+09:00", category: "수업회고")
      b = make_record(title: "B", created_at: "2024-02-01T09:00:00+09:00", category: "상담")
      c = make_record(title: "C", created_at: "2024-03-01T09:00:00+09:00", category: "수업회고")
      [a, b, c].each { |e| upsert(e) }
      link(a, b)  # 수업회고 → 상담 (cross-cat)
      link(a, c)  # 수업회고 → 수업회고

      data = repo.graph_data(category_in: ["수업회고"])
      expect(data[:nodes].map { |n| n[:title] }).to contain_exactly("A", "C")
      # b 가 노드에 없으므로 a→b 엣지 제외, a→c 만 표시
      expect(data[:edges].size).to eq(1)
      expect(data[:edges].first[:source]).to eq(a.id.to_s)
      expect(data[:edges].first[:target]).to eq(c.id.to_s)
    end
  end

  describe "필터 — mode / category / 날짜" do
    before do
      @memo = Sowing::Domain::Memo.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        body: "memo body",
        created_at: Time.parse("2024-04-01T09:00:00+09:00")
      )
      @note = Sowing::Domain::Note.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        title: "note", body: "x", category: "lessons", source: "교과서",
        created_at: Time.parse("2024-05-01T09:00:00+09:00")
      )
      @record = make_record(title: "record", created_at: "2024-06-01T09:00:00+09:00")
      [@memo, @note, @record].each { |e| upsert(e) }
    end

    it "mode_in — record 만" do
      data = repo.graph_data(mode_in: ["record"])
      expect(data[:nodes].size).to eq(1)
      expect(data[:nodes].first[:mode]).to eq("record")
    end

    it "category_in — 수업회고 만" do
      data = repo.graph_data(category_in: ["수업회고"])
      expect(data[:nodes].size).to eq(1)
      expect(data[:nodes].first[:category]).to eq("수업회고")
    end

    it "since/until — 5월만" do
      data = repo.graph_data(
        since: Time.parse("2024-05-01T00:00:00+09:00"),
        until_time: Time.parse("2024-05-31T23:59:59+09:00")
      )
      expect(data[:nodes].size).to eq(1)
      expect(data[:nodes].first[:mode]).to eq("note")
    end
  end

  describe "max_nodes 가드 + truncated 플래그" do
    it "max_nodes 초과 시 truncated true + 최근 N 만 표시" do
      6.times do |i|
        upsert(make_record(title: "n#{i}", created_at: "2024-#{i + 1}-01T09:00:00+09:00"))
      end

      data = repo.graph_data(max_nodes: 3)
      expect(data[:nodes].size).to eq(3)
      expect(data[:truncated]).to be true
      expect(data[:total]).to eq(6)
      # 최근순 — n5 (2024-06), n4, n3 가 살아남음
      expect(data[:nodes].map { |n| n[:title] }).to contain_exactly("n5", "n4", "n3")
    end

    it "max_nodes 안 초과 — truncated false" do
      upsert(make_record(title: "x", created_at: "2024-01-01T09:00:00+09:00"))
      expect(repo.graph_data(max_nodes: 100)[:truncated]).to be false
    end
  end
end
