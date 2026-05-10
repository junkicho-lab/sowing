# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::DetectOrphanEntries do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-orphans-spec-")) }
  let(:db) { Sowing::Infrastructure::DB.connection }
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

  def seed_entry(id:, body:, created_at:, mode: "memo", category: nil, title: nil, tags: [])
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

    tags.each do |tag_name|
      tid = db[:tags].where(name: tag_name).first&.dig(:id) ||
        db[:tags].insert(name: tag_name)
      db[:entry_tags].insert(entry_id: id, tag_id: tid)
    end
  end

  # source_id → target_id 링크 (links 테이블 직접). target_text 는 위키링크 표시 텍스트.
  def seed_link(source_id:, target_id:, target_text: nil)
    db[:links].insert(
      source_id: source_id,
      target_id: target_id,
      target_text: target_text || target_id
    )
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # entries 5건. 그 중 3건은 backlink 받음, 2건은 고립.
      seed_entry(id: "01ORP000000000000000A001",
        body: "민준이 발표 자원. 협동학습 효과.",
        created_at: "2026-04-15T09:00:00+09:00", mode: "memo",
        tags: ["협동학습"])
      seed_entry(id: "01ORP000000000000000A002",
        body: "수업 회고 — 협동학습 정착.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "record", category: "수업회고",
        title: "5월 회고", tags: ["협동학습", "회고"])
      seed_entry(id: "01ORP000000000000000A003",
        body: "분수 단원 어려웠다.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "memo",
        tags: ["수학"])
      # 고립 후보: 인용 받지 않음
      seed_entry(id: "01ORP000000000000000ORF",
        body: "도덕 시간 갈등 해결 — 새 시도.",
        created_at: "2026-06-01T09:00:00+09:00", mode: "note", category: "lessons",
        title: "갈등 해결 활동", tags: ["도덕"])
      seed_entry(id: "01ORP000000000000000ORG",
        body: "교사 연수 회의 메모.",
        created_at: "2026-06-15T09:00:00+09:00", mode: "memo")

      # links: A002 → A001, A002 → A003 (A001/A003 은 backlink 받음)
      seed_link(source_id: "01ORP000000000000000A002", target_id: "01ORP000000000000000A001")
      seed_link(source_id: "01ORP000000000000000A002", target_id: "01ORP000000000000000A003")
      # A002 자체는 backlink 없지만 outbound 만 있음 — 고립 후보
      # ORF, ORG 도 backlink 없음 → 고립 후보
      # 결과: A002, ORF, ORG 3건 고립
    end

    it "Success(target Pathname) — vault/.sowing/synth/orphans/observations.md" do
      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/orphans/observations.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 9키 + synth_target=orphans:observations + 태그 누적" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/orphans/observations.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("orphans:observations")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["synth_source_count"]).to eq(3)
      # 고립 entries 의 태그 모음 (회고/도덕)
      expect(fm["synth_orphan_tags"]).to include("회고", "도덕")
      expect(fm["title"]).to eq("고립 entries 관찰")
    end

    it "본문 — 3 고립 entries 인용 + 모드 분포 + 태그 분포 + outbound 주석" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/orphans/observations.md").read
      ).content

      expect(body).to include("🌊 고립 entries (3건)")
      # 3 고립 entries 의 wikilink
      expect(body).to include("[[30_Records/2026/수업회고/01ORP000000000000000A002.md]]")
      expect(body).to include("[[20_Notes/lessons/01ORP000000000000000ORF.md]]")
      expect(body).to include("[[00_Inbox/01ORP000000000000000ORG.md]]")
      # backlink 받은 A001/A003 은 등장 X
      expect(body).not_to include("01ORP000000000000000A001")
      expect(body).not_to include("01ORP000000000000000A003")
      # 모드별 분포 — 📝 1 · 📖 1 · 💭 1
      expect(body).to include("**모드별**:")
      # A002 는 outbound 2건 — "외부 링크 2건" 표시
      expect(body).to include("외부 링크 2건")
    end

    it "태그 표시 — `#태그` 형식" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/orphans/observations.md").read
      ).content
      expect(body).to include("#회고")
      expect(body).to include("#도덕")
    end

    it "결정적 trailer — '본질적 고립' 인정 톤 (단정 거부)" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/orphans/observations.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("본질적으로 고립")
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:no_orphans) — 모든 entries 가 backlink 받음" do
      seed_entry(id: "01ORPNNG000000000000A001", body: "본문 1.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01ORPNNG000000000000A002", body: "본문 2.",
        created_at: "2026-05-02T09:00:00+09:00", mode: "memo")
      # 서로 link 받음
      seed_link(source_id: "01ORPNNG000000000000A001", target_id: "01ORPNNG000000000000A002")
      seed_link(source_id: "01ORPNNG000000000000A002", target_id: "01ORPNNG000000000000A001")

      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_orphans)
    end

    it "Failure(:too_many_orphans) — > MAX (가드)" do
      stub_const("Sowing::UseCases::DetectOrphanEntries::MAX_ORPHANS", 2)
      4.times do |i|
        seed_entry(id: "01ORPMNY000000000000A0#{i + 1}", body: "x",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end
      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_orphans)
    end

    it "exclude_modes — memo 제외 가능" do
      seed_entry(id: "01ORPEXM000000000000A001", body: "메모 고립.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01ORPEXM000000000000A002", body: "필기 고립.",
        created_at: "2026-05-05T09:00:00+09:00", mode: "note", category: "lessons")

      result = use_case.call(
        since: "2026-04-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00",
        exclude_modes: ["memo"]
      )
      expect(result).to be_success
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/orphans/observations.md").read
      ).front_matter
      expect(fm["synth_source_count"]).to eq(1)  # note 만
      expect(fm["synth_excluded_modes"]).to eq(["memo"])
    end

    it "default lookback 1년 — 그 이전 entries 제외" do
      # fixed_now = 2026-07-31. 1년 전 = 2025-07-31.
      seed_entry(id: "01ORPDEF000000000000A001", body: "옛 메모 (2년 전, 범위 밖).",
        created_at: "2024-05-01T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01ORPDEF000000000000A002", body: "최근 고립.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")

      result = use_case.call
      expect(result).to be_success
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/orphans/observations.md").read
      ).front_matter
      expect(fm["synth_source_count"]).to eq(1)
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
          "## 🌊 고립 entries 의 패턴\n도덕 카테고리 누적.\n\n## 🔗 연결 후보 제안\n[1] 도덕 → #도덕 태그 다른 글들\n\n## 💭 어떤 글은 고립일 수도\n자기 회고는 본질적 고립일 수 있음.\n"
        end

        def name
          "fake:orphans"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    before do
      seed_entry(id: "01ORPLLM000000000000A001", body: "고립 메모.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
    end

    it "backend.chat 1회 + LLM 본문 반영" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(fake_backend.calls.size).to eq(1)
      content = vault_dir.join(".sowing/synth/orphans/observations.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content
      expect(fm["synth_model"]).to eq("fake:orphans")
      expect(body).to include("🔗 연결 후보 제안")
    end

    it "audit log actor=agent — LLM chat 동안" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Infrastructure::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(observed).to eq("agent")
    end

    it "LLM 실패 → 결정적 fallback" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/orphans/observations.md").read
      ).content
      expect(body).to include("결정적 합성")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "멱등 — 같은 호출 재실행 atomic 덮어쓰기" do
      seed_entry(id: "01ORPIDM000000000000A001", body: "고립 1.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      first = vault_dir.join(".sowing/synth/orphans/observations.md").mtime
      sleep 0.01
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      second = vault_dir.join(".sowing/synth/orphans/observations.md").mtime
      expect(second).to be >= first
    end

    it "vault 파일 누락 → graceful (빈 excerpt)" do
      seed_entry(id: "01ORPMSS000000000000A001", body: "고립 1.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
      vault_dir.join("00_Inbox/01ORPMSS000000000000A001.md").delete

      expect {
        use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      }.not_to raise_error
    end

    it "broken link (target_id NULL) 가 있어도 정상 — backlink 으로 카운트 안 됨" do
      seed_entry(id: "01ORPBRK000000000000A001", body: "고립 1.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
      # target_id NULL (broken link). source_id 가 BRK001 → 깨진 링크.
      # 이는 inbound 으로 카운트 안 됨 (target NULL).
      db[:links].insert(source_id: "01ORPBRK000000000000A001", target_id: nil, target_text: "없는링크")

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/orphans/observations.md").read
      ).front_matter
      # entry 자신은 여전히 고립 (backlink 0)
      expect(fm["synth_source_count"]).to eq(1)
    end
  end
end
