# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

# 4개 MCP 도구를 단위로 테스트. 도구는 ::MCP::Tool 의 self.call 클래스 메서드로 호출.
# 응답은 ::MCP::Tool::Response — content 첫 element 의 text 가 JSON 직렬화 결과.
RSpec.describe "Sowing::MCP::Tools (W9-T02)" do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("mcp-tools-spec-")) }
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
  end

  after do
    Sowing::MCP.reset!
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  def parse(response)
    text = response.content.first[:text] || response.content.first["text"]
    JSON.parse(text, symbolize_names: true)
  end

  def create_memo(body = "테스트 메모")
    Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
      .call(body: body).value!
  end

  def create_note(title: "필기", body: "본문")
    Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
      title: title, body: body, category: "lessons", source: "교과서"
    ).value!
  end

  describe Sowing::MCP::Tools::Health do
    it "버전·env·vault_dir + 모드별 카운트 + audit 상태" do
      create_memo
      create_note

      payload = parse(described_class.call)
      expect(payload[:version]).to eq(Sowing::VERSION)
      expect(payload[:env]).to be_a(String)
      expect(payload[:vault_dir]).to eq(vault_dir.to_s)
      expect(payload[:entry_counts][:memo]).to eq(1)
      expect(payload[:entry_counts][:note]).to eq(1)
      expect(payload[:entry_counts][:record]).to eq(0)
      expect(payload[:total_entries]).to eq(2)
    end

    it "빈 vault — 카운트 0" do
      payload = parse(described_class.call)
      expect(payload[:total_entries]).to eq(0)
    end
  end

  describe Sowing::MCP::Tools::ListMemos do
    before { 3.times { |i| create_memo("메모 #{i}") } }

    it "기본 — mode=memo, 3건 반환 (created_at 내림차순)" do
      payload = parse(described_class.call)
      expect(payload[:mode]).to eq("memo")
      expect(payload[:count]).to eq(3)
      expect(payload[:entries].size).to eq(3)
      expect(payload[:entries].first.keys).to include(:id, :mode, :path, :created_at)
    end

    it "limit 적용" do
      payload = parse(described_class.call(limit: 2))
      expect(payload[:count]).to eq(2)
    end

    it "offset 적용 (페이지네이션)" do
      payload = parse(described_class.call(limit: 2, offset: 2))
      expect(payload[:count]).to eq(1)
    end

    it "mode=note — 메모 외 다른 mode 만" do
      create_note
      payload = parse(described_class.call(mode: "note"))
      expect(payload[:mode]).to eq("note")
      expect(payload[:count]).to eq(1)
      expect(payload[:entries].first[:mode]).to eq("note")
    end

    it "지원하지 않는 mode → error response" do
      response = described_class.call(mode: "weird")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("지원하지 않는 mode")
    end
  end

  describe Sowing::MCP::Tools::Search do
    before do
      create_memo("협동학습 첫 시도")
      create_memo("관계없는 메모")
      create_note(title: "협동학습 정리", body: "본문")
    end

    it "q 매칭 — 메모·필기 모두" do
      payload = parse(described_class.call(q: "협동학습"))
      expect(payload[:count]).to be >= 2
      expect(payload[:entries].map { |e| e[:mode] }).to include("memo", "note")
    end

    it "mode 필터" do
      payload = parse(described_class.call(q: "협동학습", mode: "note"))
      expect(payload[:count]).to eq(1)
      expect(payload[:entries].first[:mode]).to eq("note")
    end

    it "빈 q → error" do
      response = described_class.call(q: "  ")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("q (검색어) 가 비어")
    end

    it "지원하지 않는 mode → error" do
      response = described_class.call(q: "x", mode: "alien")
      expect(response.error?).to be true
    end

    it "매칭 없음 → count 0" do
      payload = parse(described_class.call(q: "절대없는키워드xyz"))
      expect(payload[:count]).to eq(0)
      expect(payload[:entries]).to eq([])
    end
  end

  describe Sowing::MCP::Tools::ReadEntry do
    let(:memo) { create_memo("본문 내용 확인") }

    it "id 로 조회 — frontmatter + body 전체" do
      payload = parse(described_class.call(id: memo.id.to_s))
      expect(payload[:id]).to eq(memo.id.to_s)
      expect(payload[:mode]).to eq("memo")
      expect(payload[:body]).to include("본문 내용 확인")
      expect(payload[:created_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "path 로 조회" do
      indexed = index_repo.find(memo.id)
      payload = parse(described_class.call(path: indexed.path))
      expect(payload[:id]).to eq(memo.id.to_s)
    end

    it "id·path 둘 다 없으면 error" do
      response = described_class.call
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("id 또는 path")
    end

    it "없는 id → error" do
      response = described_class.call(id: "01NONEXIST00000000000000000")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("찾을 수 없습니다")
    end

    it "note 의 category·source 도 함께 반환" do
      note = create_note(title: "Note 1", body: "본문")
      payload = parse(described_class.call(id: note.id.to_s))
      expect(payload[:category]).to eq("lessons")
      expect(payload[:source]).to eq("교과서")
    end
  end

  describe "audit log 통합 — read 도구는 mutation 없음" do
    it "ListMemos / Search / ReadEntry / Health 호출은 audit 줄 추가 안 함 (read-only)" do
      memo = create_memo("기존") # 1줄 기록됨 (CreateMemo)
      Sowing::Core::AuditLog.instance.clear! # 깨끗이

      Sowing::MCP::Tools::Health.call
      Sowing::MCP::Tools::ListMemos.call
      Sowing::MCP::Tools::Search.call(q: "기존")
      Sowing::MCP::Tools::ReadEntry.call(id: memo.id.to_s)

      expect(Sowing::Core::AuditLog.instance.read_all).to be_empty
    end
  end
end
