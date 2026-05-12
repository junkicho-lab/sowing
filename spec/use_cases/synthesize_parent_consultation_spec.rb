# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeParentConsultation do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-consultation-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 7, 31, 18, 0, 0, "+09:00") }
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

  def seed_entry(id:, body:, created_at:, mode: "memo", category: nil, path: nil)
    path ||= default_path(mode, id, category, created_at)
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    fm = "id: #{id}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'"
    fm += "\ncategory: #{category}" if category
    File.write(abs, "---\n#{fm}\n---\n\n#{body}\n")

    db[:entries].insert(
      id: id, path: path, mode: mode,
      category: category,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: body.split.size, indexed_at: created_at
    )
  end

  def default_path(mode, id, category, created_at)
    case mode
    when "memo" then "00_Inbox/#{id}.md"
    when "note" then "20_Notes/#{category || "lessons"}/#{id}.md"
    when "record" then "30_Records/#{Time.iso8601(created_at).year}/#{category || "수업회고"}/#{id}.md"
    end
  end

  def seed_student(name:, entry_ids: [])
    eid = db[:entities].insert(
      type: "student", name: name,
      first_seen_at: "2026-03-01T00:00:00+09:00",
      last_seen_at: "2026-07-31T00:00:00+09:00",
      mention_count: entry_ids.size
    )
    entry_ids.each { |id| db[:entity_mentions].insert(entity_id: eid, entry_id: id) }
    eid
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # 입력 3 갈래 시드:
      # (1) 상담 record 카테고리 (학생 이름 본문 포함)
      seed_entry(id: "01PCC000000000000000R001",
        body: "민준이 학부모 상담 — 가정에서 책 읽기 시간 늘림.",
        created_at: "2026-04-15T15:00:00+09:00", mode: "record", category: "상담")
      # (2) meetings note (학부모 키워드 포함, 학생 이름은 없음)
      seed_entry(id: "01PCC000000000000000N001",
        body: "5월 학부모 면담 일정 정리.",
        created_at: "2026-05-01T10:00:00+09:00", mode: "note", category: "meetings")
      # (3) 학생 mention memo (entity 통한 매칭)
      seed_entry(id: "01PCC000000000000000M001",
        body: "민준이가 발표 자원했다. 큰 변화.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01PCC000000000000000M002",
        body: "민준이 모둠 사회자 역할 잘함.",
        created_at: "2026-06-15T09:00:00+09:00", mode: "memo")

      seed_student(name: "민준",
        entry_ids: %w[01PCC000000000000000R001 01PCC000000000000000M001 01PCC000000000000000M002])
    end

    it "Success(target Pathname) — vault/.sowing/synth/consultations/민준.md 작성" do
      result = use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/consultations/민준.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 9키 + synth_target=consultation:민준 + categories" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/consultations/민준.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("consultation:민준")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["synth_categories"]).to include("상담")
      expect(fm["title"]).to eq("학부모 상담 준비: 민준")
    end

    it "본문 — 시간순 인용 + 출처 wikilink + mode 아이콘 + 카테고리 라벨" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/consultations/민준.md").read
      ).content

      expect(body).to include("출처 entries")
      # 4 entries 통합 (3 학생 mention + 1 학부모 면담 키워드)
      expect(body).to include("[[30_Records/2026/상담/01PCC000000000000000R001.md]]")
      expect(body).to include("[[20_Notes/meetings/01PCC000000000000000N001.md]]")
      expect(body).to include("[[00_Inbox/01PCC000000000000000M001.md]]")
      expect(body).to include("[[00_Inbox/01PCC000000000000000M002.md]]")
      # mode 아이콘
      expect(body).to include("📖") # record
      expect(body).to include("📝") # note
      expect(body).to include("💭") # memo
      # 카테고리 라벨
      expect(body).to include("· 상담")
      expect(body).to include("· meetings")
    end

    it "시간순 정렬 — 4월 → 5월 → 6월" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/consultations/민준.md").read
      ).content

      apr_idx = body.index("2026-04-15")
      may_idx = body.index("2026-05-10")
      jun_idx = body.index("2026-06-15")
      expect(apr_idx).to be < may_idx
      expect(may_idx).to be < jun_idx
    end

    it "결정적 trailer — '원자료', 단정 거부 톤" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/consultations/민준.md").read
      ).content

      expect(body).to include("원자료")
      expect(body).to include("교사의 직접 판단")
    end
  end

  describe "#call — 입력 필터링" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "학생 이름·상담 키워드 둘 다 없는 entry → 제외" do
      seed_student(name: "민준", entry_ids: [])
      # 본문에 민준도 없고 학부모/면담/상담 키워드도 없음 — 제외 대상
      seed_entry(id: "01PCCEXC000000000000A001",
        body: "오늘 수업 진행함.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "상담")
      # 본문에 학생 이름 — 포함 대상
      seed_entry(id: "01PCCEXC000000000000A002",
        body: "민준이 수업 참여 좋음.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "상담")
      # 본문에 학부모 키워드 — 포함 대상
      seed_entry(id: "01PCCEXC000000000000A003",
        body: "학부모 면담 정리.",
        created_at: "2026-05-20T09:00:00+09:00", mode: "record", category: "상담")

      result = use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      content = vault_dir.join(".sowing/synth/consultations/민준.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      # 3 시드 중 2건만 (수업 진행 entry 제외)
      expect(fm["synth_source_count"]).to eq(2)
    end

    it "사용자 정의 categories override" do
      seed_student(name: "민준", entry_ids: [])
      seed_entry(id: "01PCCCAT000000000000A001",
        body: "민준 학부모 면담.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "기타상담")
      seed_entry(id: "01PCCCAT000000000000A002",
        body: "민준 학부모 면담 추가.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "기타상담")

      result = use_case.call(student_name: "민준",
        categories: ["기타상담"],
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/consultations/민준.md").read
      ).front_matter
      expect(fm["synth_categories"]).to eq(["기타상담"])
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:entity_not_found) — 학생 entity 없음" do
      result = use_case.call(student_name: "없는학생")
      expect(result).to be_failure
      expect(result.failure).to eq(:entity_not_found)
    end

    it "Failure(:no_entries) — 매칭 entries < MIN_ENTRIES (2건)" do
      seed_student(name: "민준", entry_ids: [])
      seed_entry(id: "01PCCMIN000000000000A001",
        body: "민준 학부모 면담.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "상담")

      result = use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end

    it "Failure(:too_many_entries) — entries > MAX (가드)" do
      stub_const("Sowing::UseCases::SynthesizeParentConsultation::MAX_ENTRIES", 2)
      seed_student(name: "민준", entry_ids: [])
      4.times do |i|
        seed_entry(id: "01PCCMAX0000000000000#{i + 1}",
          body: "민준 면담 #{i}.",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          mode: "record", category: "상담")
      end

      result = use_case.call(student_name: "민준",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_entries)
    end

    it "since/until 기본값 — 미지정 시 6개월 window" do
      seed_student(name: "민준", entry_ids: [])
      # fixed_now = 2026-07-31. 6개월 전 = ~2026-02-01.
      seed_entry(id: "01PCCDEF000000000000A001",
        body: "민준 면담 (범위 밖, 1월).",
        created_at: "2026-01-15T09:00:00+09:00", mode: "record", category: "상담")
      seed_entry(id: "01PCCDEF000000000000A002",
        body: "민준 면담 (범위 안, 5월).",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "상담")
      seed_entry(id: "01PCCDEF000000000000A003",
        body: "민준 면담 (범위 안, 6월).",
        created_at: "2026-06-15T09:00:00+09:00", mode: "record", category: "상담")

      result = use_case.call(student_name: "민준")
      expect(result).to be_success
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/consultations/민준.md").read
      ).front_matter
      # 1월 제외 → 2건
      expect(fm["synth_source_count"]).to eq(2)
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
          "## 🌱 학생 강점\n발표 자원 [1]\n\n## 🔄 변화 / 성장\n4월 → 5월 [2] [3]\n\n## 💬 학부모와 공유할 만한 관찰\n모둠 사회자 역할 [3]\n\n## 🤝 가정에서 함께 시도해 볼 만한 것\n- 책 읽기 시간 함께\n"
        end

        def name
          "fake:parent-consultation"
        end
      }.new
    }

    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock)
    }

    before do
      seed_entry(id: "01PCCLLM000000000000A001",
        body: "민준 학부모 면담.",
        created_at: "2026-04-15T09:00:00+09:00", mode: "record", category: "상담")
      seed_entry(id: "01PCCLLM000000000000A002",
        body: "민준이 발표 자원.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "memo")
      seed_student(name: "민준", entry_ids: %w[01PCCLLM000000000000A001 01PCCLLM000000000000A002])
    end

    it "backend.chat 1회 호출 + LLM 출력 본문 반영" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(fake_backend.calls.size).to eq(1)
      content = vault_dir.join(".sowing/synth/consultations/민준.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content

      expect(fm["synth_model"]).to eq("fake:parent-consultation")
      expect(body).to include("🤝 가정에서 함께 시도해 볼 만한 것")
    end

    it "audit log actor=agent — LLM chat 동안" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end

      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(observed).to eq("agent")
    end

    it "LLM 실패 → 결정적 폴백" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")

      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/consultations/민준.md").read
      ).content
      expect(body).to include("출처 entries")
      expect(body).to include("결정적 합성")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "멱등 — 같은 학생 재호출 시 atomic 덮어쓰기" do
      seed_student(name: "민준", entry_ids: [])
      2.times do |i|
        seed_entry(id: "01PCCIDEM00000000000A00#{i + 1}",
          body: "민준 면담 #{i}.",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          mode: "record", category: "상담")
      end

      use_case.call(student_name: "민준",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      first = vault_dir.join(".sowing/synth/consultations/민준.md").mtime
      sleep 0.01
      use_case.call(student_name: "민준",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      second = vault_dir.join(".sowing/synth/consultations/민준.md").mtime
      expect(second).to be >= first
    end

    it "vault 파일 누락 entry → graceful skip" do
      seed_student(name: "민준", entry_ids: [])
      seed_entry(id: "01PCCMISS00000000000A001",
        body: "민준 면담 1.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "상담")
      seed_entry(id: "01PCCMISS00000000000A002",
        body: "민준 면담 2.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "상담")
      # 첫 파일 직접 삭제
      vault_dir.join("30_Records/2026/상담/01PCCMISS00000000000A001.md").delete

      expect {
        use_case.call(student_name: "민준",
          since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      }.not_to raise_error
    end

    it "중복 입력 — 같은 entry 가 여러 갈래에서 매칭돼도 1회만" do
      # 학생 mention + 상담 record + 학부모 키워드 모두 만족하는 entry
      seed_entry(id: "01PCCDUP000000000000A001",
        body: "민준 학부모 면담.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "상담")
      seed_entry(id: "01PCCDUP000000000000A002",
        body: "민준 면담 추가.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "상담")
      seed_student(name: "민준",
        entry_ids: %w[01PCCDUP000000000000A001 01PCCDUP000000000000A002])

      use_case.call(student_name: "민준",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/consultations/민준.md").read
      ).front_matter
      # 2건 — 중복 카운트 X
      expect(fm["synth_source_count"]).to eq(2)
    end
  end
end
