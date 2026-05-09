# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

# W9-T03: write actuators (CreateMemo / CreateNote / CreateRecord / Promote).
# 핵심 검증: 각 도구가 entry 생성/승격에 성공 + audit log 에 actor="agent" 로 기록됨.
RSpec.describe "Sowing::MCP::Tools — write actuators (W9-T03)" do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("mcp-actuators-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Infrastructure::DB.connection }

  # Persistence 가 호출하는 AuditLog.instance 를 spec vault 로 격리.
  let!(:audit_log) { Sowing::Infrastructure::AuditLog.new(vault_dir: vault_dir) }

  before do
    Sowing::MCP.repositories = {vault: vault_repo, index: index_repo}
    Sowing::Infrastructure::AuditLog.instance = audit_log
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after do
    Sowing::MCP.reset!
    Sowing::Infrastructure::AuditLog.instance = nil
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  def parse(response)
    text = response.content.first[:text] || response.content.first["text"]
    JSON.parse(text, symbolize_names: true)
  end

  describe Sowing::MCP::Tools::CreateMemo do
    it "본문으로 메모 생성 + audit actor=agent" do
      response = described_class.call(body: "에이전트가 만든 메모")
      payload = parse(response)

      expect(payload[:mode]).to eq("memo")
      expect(payload[:id]).to match(/\A01[A-Z0-9]+/)
      expect(index_repo.count(mode: :memo)).to eq(1)

      record = audit_log.read_all.first
      expect(record["action"]).to eq("create")
      expect(record["actor"]).to eq("agent")
      expect(record["mode"]).to eq("memo")
    end

    it "tags 도 함께 저장" do
      response = described_class.call(body: "본문", tags: %w[수업 협동학습])
      payload = parse(response)
      expect(payload[:tags]).to contain_exactly("수업", "협동학습")
    end

    it "빈 body → error" do
      response = described_class.call(body: "  ")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("body 가 비어")
      expect(audit_log.read_all).to be_empty
    end
  end

  describe Sowing::MCP::Tools::CreateNote do
    it "필기 생성 + audit actor=agent" do
      response = described_class.call(
        title: "협동학습 도입", body: "본문",
        category: "lessons", source: "한국교육과정평가원"
      )
      payload = parse(response)
      expect(payload[:mode]).to eq("note")
      expect(payload[:title]).to eq("협동학습 도입")
      expect(payload[:category]).to eq("lessons")

      expect(audit_log.read_all.first["actor"]).to eq("agent")
    end

    it "잘못된 category → error" do
      response = described_class.call(
        title: "T", body: "B", category: "invalid", source: "X"
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("invalid_category")
    end

    it "빈 source → error" do
      response = described_class.call(
        title: "T", body: "B", category: "lessons", source: ""
      )
      expect(response.error?).to be true
    end
  end

  describe Sowing::MCP::Tools::CreateRecord do
    it "기록 생성 + 자유 카테고리 + audit actor=agent" do
      response = described_class.call(
        title: "5월 회고", body: "이번 달 돌아보기", category: "학급운영"
      )
      payload = parse(response)
      expect(payload[:mode]).to eq("record")
      expect(payload[:category]).to eq("학급운영")

      record = audit_log.read_all.first
      expect(record["action"]).to eq("create")
      expect(record["actor"]).to eq("agent")
      expect(record["mode"]).to eq("record")
    end

    it "빈 title → error" do
      response = described_class.call(title: "", body: "x", category: "회고")
      expect(response.error?).to be true
    end
  end

  describe Sowing::MCP::Tools::Promote do
    # let! 로 eager-evaluate — 그래야 clear! 시점이 명확.
    let!(:memo) {
      Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "승격 대상").value!
    }

    it "memo → note 승격: ID 유지 + actor=agent + mode 변경" do
      audit_log.clear! # CreateMemo 가 남긴 :create 줄 정리

      response = described_class.call(
        id: memo.id.to_s, to: "note", title: "승격된 필기",
        category: "lessons", source: "교과서"
      )
      payload = parse(response)

      expect(payload[:id]).to eq(memo.id.to_s) # ID 유지
      expect(payload[:mode]).to eq("note")
      expect(payload[:promoted_to]).to eq("note")

      record = audit_log.read_all.first
      expect(record["action"]).to eq("update") # 승격은 update
      expect(record["actor"]).to eq("agent")
      expect(record["mode"]).to eq("note") # 승격 후 모드
      expect(record["entry_id"]).to eq(memo.id.to_s)
    end

    it "memo → record 승격" do
      audit_log.clear!
      response = described_class.call(
        id: memo.id.to_s, to: "record", title: "승격된 기록", category: "회고"
      )
      payload = parse(response)
      expect(payload[:mode]).to eq("record")
      expect(payload[:promoted_to]).to eq("record")
      expect(audit_log.read_all.first["actor"]).to eq("agent")
    end

    it "to 가 잘못된 값 → error" do
      response = described_class.call(
        id: memo.id.to_s, to: "weird", title: "T", category: "lessons"
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("to 는 'note' 또는 'record'")
    end

    it "to=note 인데 source 누락 → error" do
      response = described_class.call(
        id: memo.id.to_s, to: "note", title: "T", category: "lessons"
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("source")
    end

    it "없는 id → Use Case Failure 전달" do
      response = described_class.call(
        id: "01NONEXIST00000000000000000", to: "note",
        title: "T", category: "lessons", source: "X"
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("not_found")
    end

    it "이미 필기인 entry 를 to=note 로 승격 → Failure(:not_a_memo)" do
      note = Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
        title: "원래 필기", body: "본문", category: "lessons", source: "X"
      ).value!

      response = described_class.call(
        id: note.id.to_s, to: "note", title: "T",
        category: "lessons", source: "X"
      )
      expect(response.error?).to be true
    end
  end

  describe "Server::TOOLS 등록" do
    it "8개 도구 모두 등록 (sensor 4 + actuator 4)" do
      names = Sowing::MCP::Server::TOOLS.map(&:tool_name)
      expect(names).to contain_exactly(
        "list_memos", "search", "read_entry", "health",
        "create_memo", "create_note", "create_record", "promote"
      )
    end
  end

  describe "audit log 다중 mutation 시나리오" do
    it "create_memo + promote + create_record → 3줄 모두 actor=agent" do
      Sowing::MCP::Tools::CreateMemo.call(body: "메모")
      memo_id = index_repo.list(mode: :memo).first.id.to_s

      Sowing::MCP::Tools::Promote.call(
        id: memo_id, to: "note", title: "승격",
        category: "lessons", source: "X"
      )

      Sowing::MCP::Tools::CreateRecord.call(
        title: "기록", body: "본문", category: "회고"
      )

      records = audit_log.read_all
      expect(records.size).to eq(3)
      expect(records.map { |r| r["actor"] }).to all(eq("agent"))
      expect(records.map { |r| r["action"] }).to eq(%w[create update create])
    end
  end
end
