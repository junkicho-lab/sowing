# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

# W9-T04: analytics sensors (StatsSummary / TagCloud / WikiComplete / Recent).
RSpec.describe "Sowing::MCP::Tools — analytics sensors (W9-T04)" do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("mcp-analytics-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Core::DB.connection }

  before do
    Sowing::MCP.repositories = {vault: vault_repo, index: index_repo}
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    db[:daily_stats].delete
  end

  after do
    Sowing::MCP.reset!
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  def parse(response)
    text = response.content.first[:text] || response.content.first["text"]
    JSON.parse(text, symbolize_names: true)
  end

  def create_memo(body, tags: [])
    Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
      .call(body: body, tags: tags).value!
  end

  def create_note(title:, body: "본문")
    Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
      title: title, body: body, category: "lessons", source: "교과서"
    ).value!
  end

  describe Sowing::MCP::Tools::StatsSummary do
    it "빈 vault — 모든 카운트 0, growth=empty" do
      payload = parse(described_class.call)
      expect(payload[:today][:total]).to eq(0)
      expect(payload[:this_week]).to eq(0)
      expect(payload[:this_month]).to eq(0)
      expect(payload[:streak_days]).to eq(0)
      expect(payload[:total_all_time]).to eq(0)
      expect(payload[:growth][:stage]).to eq("empty")
    end

    it "오늘 메모 2건 + 필기 1건 → 카운트 + growth=seed" do
      create_memo("메모 1")
      create_memo("메모 2")
      create_note(title: "필기")

      payload = parse(described_class.call)
      expect(payload[:today][:total]).to eq(3)
      expect(payload[:today][:memos]).to eq(2)
      expect(payload[:today][:notes]).to eq(1)
      expect(payload[:streak_days]).to eq(1)
      expect(payload[:total_all_time]).to eq(3)
      expect(payload[:growth][:stage]).to eq("seed")
      expect(payload[:growth][:next_threshold]).to eq(10)
    end

    it "growth payload — stage·label·message·progress 모두 포함" do
      create_memo("X")
      payload = parse(described_class.call)
      g = payload[:growth]
      expect(g.keys).to include(:stage, :label, :message, :next_threshold, :remaining_to_next, :progress_ratio)
      expect(g[:progress_ratio]).to be_a(Numeric)
    end
  end

  describe Sowing::MCP::Tools::TagCloud do
    before do
      create_memo("A", tags: %w[수업 협동학습])
      create_memo("B", tags: %w[수업])
      create_memo("C", tags: %w[회고])
    end

    it "사용 빈도 desc + 태그 정보 반환" do
      payload = parse(described_class.call)
      expect(payload[:count]).to eq(3)
      expect(payload[:tags].first[:name]).to eq("수업")
      expect(payload[:tags].first[:count]).to eq(2)
    end

    it "limit 적용 — 상위 N개" do
      payload = parse(described_class.call(limit: 2))
      expect(payload[:tags].size).to eq(2)
    end

    it "빈 vault — count 0" do
      db[:entry_tags].delete
      db[:tags].delete
      db[:entries].delete

      payload = parse(described_class.call)
      expect(payload[:count]).to eq(0)
      expect(payload[:tags]).to eq([])
    end
  end

  describe Sowing::MCP::Tools::WikiComplete do
    before do
      create_note(title: "협동학습 도입")
      create_note(title: "협동학습 회고")
      create_note(title: "수업 정리")
    end

    it "q substring 매칭" do
      payload = parse(described_class.call(q: "협동"))
      titles = payload[:candidates].map { |c| c[:title] }
      expect(titles).to contain_exactly("협동학습 도입", "협동학습 회고")
    end

    it "빈 q — 모든 후보 (note title 있는 것)" do
      payload = parse(described_class.call(q: ""))
      expect(payload[:count]).to eq(3)
    end

    it "메모는 title 없어 매칭 제외" do
      create_memo("메모 본문에 협동학습 들어있음", tags: [])
      payload = parse(described_class.call(q: "협동"))
      modes = payload[:candidates].map { |c| c[:mode] }
      expect(modes).to all(eq("note"))
    end

    it "limit 적용" do
      payload = parse(described_class.call(q: "", limit: 2))
      expect(payload[:count]).to eq(2)
    end
  end

  describe Sowing::MCP::Tools::Recent do
    it "모든 모드 통합 최근순" do
      memo = create_memo("메모")
      note = create_note(title: "필기")

      payload = parse(described_class.call)
      ids = payload[:entries].map { |e| e[:id] }
      expect(ids).to contain_exactly(memo.id.to_s, note.id.to_s)
      # ULID 의 시간 순서는 보장되므로 마지막에 만든 것이 first
      expect(payload[:entries].first[:mode]).to eq("note")
    end

    it "limit 적용" do
      3.times { |i| create_memo("메모 #{i}") }
      payload = parse(described_class.call(limit: 2))
      expect(payload[:count]).to eq(2)
    end

    it "빈 vault — count 0" do
      payload = parse(described_class.call)
      expect(payload[:count]).to eq(0)
      expect(payload[:entries]).to eq([])
    end
  end

  describe "Server::TOOLS 등록 (12개)" do
    it "sensor 4 + actuator 4 + analytics 4 = 12 도구" do
      names = Sowing::MCP::Server::TOOLS.map(&:tool_name)
      expect(names.size).to eq(12)
      # 신규 4개 추가 확인
      expect(names).to include("stats_summary", "tag_cloud", "wiki_complete", "recent")
    end
  end

  describe "audit log 통합 — analytics 도구는 read-only" do
    it "StatsSummary / TagCloud / WikiComplete / Recent 호출은 audit 줄 추가 안 함" do
      create_memo("기존")
      Sowing::Core::AuditLog.instance.clear!

      Sowing::MCP::Tools::StatsSummary.call
      Sowing::MCP::Tools::TagCloud.call
      Sowing::MCP::Tools::WikiComplete.call(q: "x")
      Sowing::MCP::Tools::Recent.call

      expect(Sowing::Core::AuditLog.instance.read_all).to be_empty
    end
  end
end

RSpec.describe "Sowing::Repositories::IndexRepo#recent_across (W9-T04)" do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("recent-across-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Core::DB.connection }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  it "모든 모드 created_at 내림차순" do
    Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo).call(body: "M")
    Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
      title: "N", body: "B", category: "lessons", source: "X"
    )
    Sowing::UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo).call(
      title: "R", body: "B", category: "회고"
    )

    entries = index_repo.recent_across(limit: 5)
    expect(entries.size).to eq(3)
    expect(entries.map(&:mode)).to eq(%i[record note memo]) # 가장 늦게 만든 것이 first
  end

  it "limit 기본 10" do
    11.times { |i| Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo).call(body: "M#{i}") }
    expect(index_repo.recent_across.size).to eq(10)
  end

  it "빈 인덱스 → 빈 배열" do
    expect(index_repo.recent_across).to eq([])
  end
end
