# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeLessonSeries do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-series-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 7, 31, 18, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }

  before do
    db[:entry_tags].delete
    db[:tags].delete
    db[:links].delete
    db[:entries_fts].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  def seed_entry(id:, body:, created_at:, mode: "memo", category: nil, title: nil)
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
      word_count: body.split.size, indexed_at: created_at
    )
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # "분수" 단원 4차시 시뮬레이션 — title 또는 body 매칭
      seed_entry(id: "01LSF000000000000000A001",
        body: "분수 단원 1차시 — 직관적 도입.",
        created_at: "2026-05-04T09:00:00+09:00", mode: "note", category: "lessons",
        title: "분수 1차시")
      seed_entry(id: "01LSF000000000000000A002",
        body: "민준이 분수 풀이 자원.",
        created_at: "2026-05-08T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01LSF000000000000000A003",
        body: "분수 단원 3차시 — 통분 도입.",
        created_at: "2026-05-12T09:00:00+09:00", mode: "note", category: "lessons",
        title: "분수 3차시")
      seed_entry(id: "01LSF000000000000000A004",
        body: "분수 단원 마무리 — 평가.",
        created_at: "2026-05-20T09:00:00+09:00", mode: "record", category: "수업회고",
        title: "분수 단원 회고")
      # 무관 entry — 매칭 안 됨
      seed_entry(id: "01LSF000000000000000B001",
        body: "체육 줄넘기.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "memo", title: "체육")
    end

    it "Success(target Pathname) — vault/.sowing/synth/lesson-series/분수.md" do
      result = use_case.call(keyword: "분수",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/lesson-series/분수.md")
      expect(target).to exist
    end

    it "frontmatter 12키 + synth_target=series:분수 + status 자동 (종료/진행)" do
      use_case.call(keyword: "분수",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/lesson-series/분수.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("series:분수")
      expect(fm["synth_keyword"]).to eq("분수")
      expect(fm["synth_source_count"]).to eq(4)  # 분수 매칭 4건, 체육 제외
      # last entry = 5/20, fixed_now = 7/31, 차이 72일 → 종료
      expect(fm["synth_status"]).to eq("ended")
      expect(fm["synth_first_date"]).to start_with("2026-05-04")
      expect(fm["synth_last_date"]).to start_with("2026-05-20")
      expect(fm["title"]).to eq("수업 시리즈: 분수")
    end

    it "본문 — 차시별 timeline + mode 아이콘 + 종료 표시 + wikilink" do
      use_case.call(keyword: "분수",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/lesson-series/분수.md").read
      ).content

      expect(body).to include("✅ 종료된 시리즈")
      expect(body).to include("📋 차시별 timeline (4건")
      # 모든 매칭 entry 의 wikilink
      expect(body).to include("[[20_Notes/lessons/01LSF000000000000000A001.md]]")
      expect(body).to include("[[00_Inbox/01LSF000000000000000A002.md]]")
      expect(body).to include("[[30_Records/2026/수업회고/01LSF000000000000000A004.md]]")
      # 체육 entry 는 매칭 안 됨
      expect(body).not_to include("01LSF000000000000000B001")
      # mode 아이콘
      expect(body).to include("💭")
      expect(body).to include("📝")
      expect(body).to include("📖")
    end

    it "결정적 trailer — 단정 거부 톤" do
      use_case.call(keyword: "분수",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/lesson-series/분수.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("단정 X")
    end

    it "진행 중 시리즈 — 마지막 entry 14일 미만 경과 시 🟢" do
      # fixed_now 가까운 entry 시드
      seed_entry(id: "01LSACT00000000000000A01",
        body: "체육 줄넘기 1차시.",
        created_at: "2026-07-25T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01LSACT00000000000000A02",
        body: "체육 줄넘기 2차시.",
        created_at: "2026-07-30T09:00:00+09:00", mode: "memo")

      use_case.call(keyword: "체육",
        since: "2026-07-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/lesson-series/체육.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content

      expect(fm["synth_status"]).to eq("active")
      expect(body).to include("🟢 진행 중인 시리즈")
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:invalid_keyword) — 빈 키워드" do
      result = use_case.call(keyword: "")
      expect(result).to be_failure
      expect(result.failure).to eq(:invalid_keyword)
    end

    it "Failure(:no_entries) — 매칭 < MIN_ENTRIES" do
      seed_entry(id: "01LSMIN00000000000000A01",
        body: "분수 1번만.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
      result = use_case.call(keyword: "분수",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end

    it "Failure(:too_many_entries) — > MAX (가드)" do
      stub_const("Sowing::UseCases::SynthesizeLessonSeries::MAX_ENTRIES", 2)
      4.times do |i|
        seed_entry(id: "01LSMAX00000000000000A0#{i + 1}",
          body: "분수 #{i}.",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end
      result = use_case.call(keyword: "분수",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_entries)
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
          "## 🎒 단원 흐름\n분수 4차시.\n\n## 👥 학생 반응 변화\n민준 자원 [2]\n\n## 🌱 잘된 차시\n3차시\n\n## 📚 다음 단원 준비\n- 통분 보조과제\n"
        end

        def name
          "fake:lesson-series"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    before do
      seed_entry(id: "01LSLLM00000000000000A01", body: "분수 1차시.",
        created_at: "2026-05-04T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01LSLLM00000000000000A02", body: "분수 2차시.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "memo")
    end

    it "backend.chat 1회 + LLM 본문 + agent actor + 실패 fallback" do
      use_case.call(keyword: "분수",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(fake_backend.calls.size).to eq(1)
      content = vault_dir.join(".sowing/synth/lesson-series/분수.md").read
      expect(content).to include("📚 다음 단원 준비")

      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call(keyword: "분수",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(observed).to eq("agent")

      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(keyword: "분수",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/lesson-series/분수.md").read
      ).content
      expect(body).to include("결정적 합성")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "title 매칭 + body 매칭 — 둘 중 하나만 만족해도 포함" do
      seed_entry(id: "01LSTLB00000000000000A01",
        body: "오늘 수업 끝.",  # body 에 "분수" 없음
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo", title: "분수 1차시")
      seed_entry(id: "01LSTLB00000000000000A02",
        body: "분수 단원 진행.",  # body 에 있음
        created_at: "2026-05-05T09:00:00+09:00", mode: "memo", title: "오늘")

      result = use_case.call(keyword: "분수",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/lesson-series/분수.md").read
      ).front_matter
      expect(fm["synth_source_count"]).to eq(2)
    end

    it "멱등 — 같은 키워드 재호출 atomic 덮어쓰기" do
      2.times do |i|
        seed_entry(id: "01LSIDM00000000000000A0#{i + 1}",
          body: "분수 #{i}.",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end
      use_case.call(keyword: "분수",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      first = vault_dir.join(".sowing/synth/lesson-series/분수.md").mtime
      sleep 0.01
      use_case.call(keyword: "분수",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      second = vault_dir.join(".sowing/synth/lesson-series/분수.md").mtime
      expect(second).to be >= first
    end
  end
end
