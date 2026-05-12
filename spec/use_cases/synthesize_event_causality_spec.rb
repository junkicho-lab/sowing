# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeEventCausality do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-event-causality-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 7, 31, 12, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }

  before do
    db[:entity_mentions].delete
    db[:entities].delete
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  let(:seed_counter) { @seed_counter ||= [0] }

  def seed_entry(title:, body:, created_at:, mode: "memo", category: nil)
    seed_counter[0] += 1
    rid = "01EVT" + format("%021d", seed_counter[0])
    path = case mode
    when "memo" then "00_Inbox/#{rid}.md"
    when "note" then "20_Notes/#{category || "lessons"}/#{rid}.md"
    when "record" then "30_Records/#{Time.iso8601(created_at).year}/#{category || "회고"}/#{rid}.md"
    end
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    fm = "id: #{rid}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\ntitle: #{title}"
    fm += "\ncategory: #{category}" if category
    File.write(abs, "---\n#{fm}\n---\n\n#{body}\n")
    db[:entries].insert(
      id: rid, path: path, mode: mode, category: category, title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "0" * 16,
      word_count: body.split.size, indexed_at: created_at
    )
    rid
  end

  def seed_student(name:, entry_ids:)
    eid = db[:entities].insert(
      type: "student", name: name,
      first_seen_at: "2026-01-01T00:00:00+09:00",
      last_seen_at: "2026-12-31T00:00:00+09:00",
      mention_count: entry_ids.size
    )
    entry_ids.each { |id| db[:entity_mentions].insert(entity_id: eid, entry_id: id) }
  end

  describe "#call (결정적)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # before window (4월): 일반 entries — 부정 신호어 + 학생 A
      seed_entry(title: "수업 어려웠다", body: "분수 어려웠다.",
        created_at: "2026-04-10T09:00:00+09:00")
      b2 = seed_entry(title: "수업 산만", body: "민준이 수업 산만했다.",
        created_at: "2026-04-15T09:00:00+09:00")
      seed_entry(title: "회의", body: "학년 회의.",
        created_at: "2026-04-20T09:00:00+09:00", mode: "note", category: "meetings")

      # event 시점 (5/1): 협동학습 도입
      seed_entry(title: "협동학습 첫 도입", body: "협동학습 시작.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "record", category: "수업회고")

      # after window (5/2 ~ 5/31): 긍정 신호어 + 새 학생 mention
      seed_entry(title: "활기찬 수업", body: "협동학습 잘됐다. 보람 있었다.",
        created_at: "2026-05-08T09:00:00+09:00")
      a2 = seed_entry(title: "민준 발표", body: "민준이 자원 발표 뿌듯.",
        created_at: "2026-05-15T09:00:00+09:00")
      a3 = seed_entry(title: "서연 변화", body: "서연이 협력적으로 변함.",
        created_at: "2026-05-22T09:00:00+09:00")

      seed_student(name: "민준", entry_ids: [b2, a2])
      seed_student(name: "서연", entry_ids: [a3])
    end

    it "Success — vault/.sowing/synth/event-causality/{keyword}.md" do
      result = use_case.call(event_keyword: "협동학습", window_days: 30)
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/event-causality/협동학습.md")).to exist
    end

    it "frontmatter — synth_event_at + window_days + before/after counts" do
      use_case.call(event_keyword: "협동학습", window_days: 30)
      content = vault_dir.join(".sowing/synth/event-causality/협동학습.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["synth_event_keyword"]).to eq("협동학습")
      expect(fm["synth_event_at"]).to start_with("2026-05-01")
      expect(fm["synth_window_days"]).to eq(30)
      expect(fm["synth_before_count"]).to be >= 3
      expect(fm["synth_after_count"]).to be >= 3
      expect(fm["synth_event_occurrences"]).to be >= 1
    end

    it "본문 — before/after 표 + 새 학생 + trailer 인과 거부" do
      use_case.call(event_keyword: "협동학습", window_days: 30)
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/event-causality/협동학습.md").read
      ).content

      expect(body).to include("Before vs After")
      expect(body).to include("긍정 신호어")
      expect(body).to include("부정 신호어")
      # 새로 등장 학생 (서연은 before 에 없음)
      expect(body).to include("새로 등장한 학생")
      expect(body).to include("- 서연")
      expect(body).to include("상관 = 인과 아님")
    end

    it "before/after 톤 변화 화살표 (긍정 ↑, 부정 ↓)" do
      use_case.call(event_keyword: "협동학습", window_days: 30)
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/event-causality/협동학습.md").read
      ).content

      # 긍정 신호어 — before 0 vs after N → ↑
      table = body[/## 📊 Before vs After[\s\S]*?(?=^##)/m]
      expect(table).to match(/긍정 신호어.*↑/)
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "invalid_keyword" do
      expect(use_case.call(event_keyword: "").failure).to eq(:invalid_keyword)
    end

    it "event_not_found — 키워드가 어떤 entry 에도 없음" do
      seed_entry(title: "수업", body: "본문", created_at: "2026-05-01T09:00:00+09:00")
      result = use_case.call(event_keyword: "없는키워드")
      expect(result).to be_failure
      expect(result.failure).to eq(:event_not_found)
    end

    it "no_entries — total < MIN_TOTAL_ENTRIES (5)" do
      seed_entry(title: "협동학습", body: "x", created_at: "2026-05-01T09:00:00+09:00")
      seed_entry(title: "tail", body: "x", created_at: "2026-05-15T09:00:00+09:00")
      result = use_case.call(event_keyword: "협동학습", window_days: 30)
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end
  end

  describe "#call (LLM 모드)" do
    let(:fake_backend) {
      Class.new {
        attr_reader :calls
        def initialize
          @calls = []
        end

        def chat(system:, user:)
          @calls << {system: system, user: user}
          "## 📊 관찰된 변화\n긍정 증가.\n\n## 🤔 가능한 상관 패턴\n관련일 수도.\n\n## 📝 본문에 명시된 사건\n없음.\n\n## 💡 다음 검증 제안\n- 추가 관찰.\n"
        end

        def name
          "fake:event-causality"
        end
      }.new
    }

    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock)
    }

    before do
      seed_entry(title: "전 1", body: "x", created_at: "2026-04-10T09:00:00+09:00")
      seed_entry(title: "전 2", body: "x", created_at: "2026-04-15T09:00:00+09:00")
      seed_entry(title: "전 3", body: "x", created_at: "2026-04-20T09:00:00+09:00")
      seed_entry(title: "협동학습", body: "도입.", created_at: "2026-05-01T09:00:00+09:00")
      seed_entry(title: "후 1", body: "잘됐다.", created_at: "2026-05-10T09:00:00+09:00")
      seed_entry(title: "후 2", body: "보람 있었다.", created_at: "2026-05-20T09:00:00+09:00")
      seed_entry(title: "후 3", body: "활기.", created_at: "2026-05-25T09:00:00+09:00")
    end

    it "backend.chat 1회 + agent actor + LLM 본문" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call(event_keyword: "협동학습", window_days: 30)
      expect(fake_backend.calls.size).to eq(1)
      expect(observed).to eq("agent")
      content = vault_dir.join(".sowing/synth/event-causality/협동학습.md").read
      expect(content).to include("관찰된 변화")
    end

    it "LLM 실패 → 결정적 fallback" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "x")
      result = use_case.call(event_keyword: "협동학습", window_days: 30)
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/event-causality/협동학습.md").read).to include("결정적 합성")
    end
  end
end
