# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeSeasonalPattern do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-seasonal-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 5, 15, 12, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }

  before do
    db[:entries_fts].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  def seed_entry(id:, created_at:, body: "x", mode: "memo", category: nil, title: nil)
    path = case mode
    when "memo" then "00_Inbox/#{id}.md"
    when "note" then "20_Notes/#{category || "lessons"}/#{id}.md"
    when "record" then "30_Records/#{Time.iso8601(created_at).year}/#{category || "수업회고"}/#{id}.md"
    end
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    fm = "id: #{id}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'"
    fm += "\ncategory: #{category}" if category
    fm += "\ntitle: #{title}" if title
    File.write(abs, "---\n#{fm}\n---\n\n#{body}\n")

    db[:entries].insert(
      id: id, path: path, mode: mode, category: category, title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: 1, indexed_at: created_at
    )
  end

  describe "#call (결정적 모드, 다년 누적)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # 5월 — 3년치 (2024, 2025, 2026)
      seed_entry(id: "01SEA00000000000000Y2401",
        body: "2024년 5월 — 협동학습 첫 시도.",
        created_at: "2024-05-10T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01SEA00000000000000Y2402",
        body: "2024년 5월 — 학부모 면담.",
        created_at: "2024-05-20T09:00:00+09:00", mode: "record", category: "상담", title: "5월 상담")
      seed_entry(id: "01SEA00000000000000Y2501",
        body: "2025년 5월 — 협동학습 정착.",
        created_at: "2025-05-15T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01SEA00000000000000Y2502",
        body: "2025년 5월 — 분수 단원.",
        created_at: "2025-05-25T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01SEA00000000000000Y2601",
        body: "2026년 5월 — 올해도 협동학습.",
        created_at: "2026-05-05T09:00:00+09:00", mode: "memo")
      # 6월 entry — 5월 합성 시 제외돼야 함
      seed_entry(id: "01SEA00000000000000Y2603",
        body: "6월 — 도덕.",
        created_at: "2026-06-10T09:00:00+09:00", mode: "memo")
    end

    it "Success(target Pathname) — vault/.sowing/synth/seasonal/05.md (이번 달 자동)" do
      result = use_case.call  # month nil → fixed_now (5월) 자동
      expect(result).to be_success
      target = vault_dir.join(".sowing/synth/seasonal/05.md")
      expect(target).to exist
    end

    it "month 인자 명시 → 해당 월 파일" do
      result = use_case.call(month: 5)
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/seasonal/05.md")).to exist
    end

    it "frontmatter — synth_target=season:05 + 연도 목록 + 연도별 카운트 + pattern_eligible" do
      use_case.call(month: 5)
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/seasonal/05.md").read
      ).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("season:05")
      expect(fm["synth_month"]).to eq(5)
      expect(fm["synth_years"]).to eq([2024, 2025, 2026])
      expect(fm["synth_year_counts"]).to eq({2024 => 2, 2025 => 2, 2026 => 1})
      expect(fm["synth_current_year"]).to eq(2026)
      expect(fm["synth_pattern_eligible"]).to be true  # 3년 ≥ MIN_YEARS=2
      expect(fm["synth_source_count"]).to eq(5)  # 5월 5건, 6월 제외
      expect(fm["title"]).to eq("계절성 패턴: 05월")
    end

    it "본문 — 연도별 timeline + 올해 마커 + 모드 분포" do
      use_case.call(month: 5)
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/seasonal/05.md").read
      ).content

      expect(body).to include("🍂 05월 계절성 패턴")
      expect(body).to include("**연도별**: 2024 2건 · 2025 2건 · 2026 1건")
      expect(body).to include("2024년 — 2건")
      expect(body).to include("2025년 — 2건")
      # 올해 마커
      expect(body).to include("2026년 🎯 (올해)")
      # wikilink 인용
      expect(body).to include("[[00_Inbox/01SEA00000000000000Y2401.md]]")
      expect(body).to include("[[30_Records/2024/상담/01SEA00000000000000Y2402.md]]")
      # 6월 entry 는 등장 X
      expect(body).not_to include("01SEA00000000000000Y2603")
    end

    it "결정적 trailer — 단정 거부 톤" do
      use_case.call(month: 5)
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/seasonal/05.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("'이 시기에 항상 ~한다' 단정 X")
    end
  end

  describe "#call — 1년 미만 (씨를 뿌리는 단계)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "1년치 만 — pattern_eligible false + 안내 문구" do
      3.times do |i|
        seed_entry(id: "01SEA00000000000000ONE0#{i + 1}",
          body: "올해만.",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end

      use_case.call(month: 5)
      content = vault_dir.join(".sowing/synth/seasonal/05.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content

      expect(fm["synth_pattern_eligible"]).to be false
      expect(fm["synth_years"]).to eq([2026])
      expect(body).to include("씨를 뿌리는 단계")
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:invalid_month) — 0 또는 13" do
      expect(use_case.call(month: 0).failure).to eq(:invalid_month)
      expect(use_case.call(month: 13).failure).to eq(:invalid_month)
    end

    it "Failure(:no_entries) — 해당 월 < MIN_ENTRIES" do
      seed_entry(id: "01SEA00000000000000NOE001",
        body: "1번만.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01SEA00000000000000NOE002",
        body: "2번만.",
        created_at: "2026-05-05T09:00:00+09:00", mode: "memo")

      result = use_case.call(month: 5)
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end

    it "Failure(:too_many_entries) — > MAX (가드)" do
      stub_const("Sowing::UseCases::SynthesizeSeasonalPattern::MAX_ENTRIES", 2)
      4.times do |i|
        seed_entry(id: "01SEA00000000000000MAX0#{i + 1}",
          body: "x",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end
      result = use_case.call(month: 5)
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_entries)
    end
  end

  describe "#call (LLM 모드)" do
    let(:fake_backend) {
      Class.new {
        attr_reader :calls, :last_system

        def initialize
          @calls = []
        end

        def chat(system:, user:)
          @calls << {system: system, user: user}
          @last_system = system
          "## 🔁 매년 반복되는 패턴\n협동학습 N년 모두 [1]\n\n## 🌊 매년 다른 점\n2026 분수 도입.\n\n## 🎯 올해 시도해 볼 만한 것\n- 모둠 차별 보조과제\n"
        end

        def name
          "fake:seasonal"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    before do
      # 2년치 → pattern_eligible
      seed_entry(id: "01SEALLM0000000000Y25001",
        body: "x", created_at: "2025-05-10T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01SEALLM0000000000Y25002",
        body: "x", created_at: "2025-05-20T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01SEALLM0000000000Y26001",
        body: "x", created_at: "2026-05-05T09:00:00+09:00", mode: "memo")
    end

    it "1회 호출 + 비교 prompt + agent actor + 실패 fallback" do
      use_case.call(month: 5)
      expect(fake_backend.calls.size).to eq(1)
      # pattern_eligible 인 경우 비교 prompt
      expect(fake_backend.last_system).to include("매년 반복")

      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call(month: 5)
      expect(observed).to eq("agent")

      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(month: 5)
      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/seasonal/05.md").read
      ).content
      expect(body).to include("결정적 합성")
    end

    it "1년 미만이면 LLM prompt 도 단순 (이번 달 흐름만)" do
      db[:entries].where(Sequel.like(:id, "01SEALLM0000000000Y25%")).delete
      # 2026 만 — MIN_ENTRIES=3 충족 위해 추가 시드
      seed_entry(id: "01SEALLM0000000000Y26002",
        body: "x", created_at: "2026-05-12T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01SEALLM0000000000Y26003",
        body: "x", created_at: "2026-05-18T09:00:00+09:00", mode: "memo")

      result = use_case.call(month: 5)
      expect(result).to be_success
      expect(fake_backend.last_system).to include("이번 달 흐름")
      expect(fake_backend.last_system).not_to include("매년 반복")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "멱등 — 같은 월 재호출 atomic 덮어쓰기" do
      3.times do |i|
        seed_entry(id: "01SEAIDM00000000000Y26#{i + 1}",
          body: "x",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end
      use_case.call(month: 5)
      first = vault_dir.join(".sowing/synth/seasonal/05.md").mtime
      sleep 0.01
      use_case.call(month: 5)
      second = vault_dir.join(".sowing/synth/seasonal/05.md").mtime
      expect(second).to be >= first
    end

    it "month=12 (12월) 처리 — 0 패딩 정상" do
      3.times do |i|
        seed_entry(id: "01SEADC00000000000Y2612#{i}",
          body: "x",
          created_at: "2026-12-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end
      result = use_case.call(month: 12)
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/seasonal/12.md")).to exist
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/seasonal/12.md").read
      ).front_matter
      expect(fm["synth_target"]).to eq("season:12")
    end
  end
end
