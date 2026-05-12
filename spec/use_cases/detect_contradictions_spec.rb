# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::DetectContradictions do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-contradictions-spec-")) }
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

  def seed_entry(id:, body:, created_at:, mode: "memo")
    path = "00_Inbox/#{id}.md"
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    File.write(abs, "---\nid: #{id}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\n---\n\n#{body}\n")

    db[:entries].insert(
      id: id, path: path, mode: mode,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: body.split.size, indexed_at: created_at
    )
  end

  def seed_student_with_mentions(name:, entry_ids:)
    eid = db[:entities].insert(
      type: "student", name: name,
      first_seen_at: "2026-04-01T00:00:00+09:00",
      last_seen_at: "2026-07-31T00:00:00+09:00",
      mention_count: entry_ids.size
    )
    entry_ids.each { |id| db[:entity_mentions].insert(entity_id: eid, entry_id: id) }
    eid
  end

  describe "#call (결정적 모드) — 의도적 모순 5종" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "[1] 참여도 변화 — '발표를 거의 안' (4월) → '발표 자원' (5월)" do
      seed_entry(id: "01CON0000000000000000A001",
        body: "민준이는 발표를 거의 안 한다. 시선도 잘 마주치지 않음.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01CON0000000000000000A002",
        body: "민준이가 오늘 처음으로 발표를 자원했다.",
        created_at: "2026-05-05T09:00:00+09:00")
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CON0000000000000000A001 01CON0000000000000000A002])

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/contradictions/observations.md").read
      ).content

      expect(body).to include("민준 · 참여도")
      expect(body).to include("→ 향상")
      expect(body).to include("2026-04-12 → 2026-05-05")
    end

    it "[2] 집중도 변화 — '산만' (4월) → '집중' (6월)" do
      seed_entry(id: "01CON0000000000000000B001",
        body: "서연이가 수학 시간에 산만했다.",
        created_at: "2026-04-10T09:00:00+09:00")
      seed_entry(id: "01CON0000000000000000B002",
        body: "서연이가 도덕 시간에 깊이 집중했다.",
        created_at: "2026-06-15T09:00:00+09:00")
      seed_student_with_mentions(name: "서연", entry_ids: %w[01CON0000000000000000B001 01CON0000000000000000B002])

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/contradictions/observations.md").read
      ).content

      expect(body).to include("서연 · 집중도")
      expect(body).to include("→ 향상")
    end

    it "[3] 이해도 변화 — '어려워' (4월) → '또래 이상' (6월)" do
      seed_entry(id: "01CON0000000000000000C001",
        body: "지호가 분수 단원을 어려워한다.",
        created_at: "2026-04-20T09:00:00+09:00")
      seed_entry(id: "01CON0000000000000000C002",
        body: "지호의 분수 풀이가 또래 이상으로 정확하다.",
        created_at: "2026-06-25T09:00:00+09:00")
      seed_student_with_mentions(name: "지호", entry_ids: %w[01CON0000000000000000C001 01CON0000000000000000C002])

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/contradictions/observations.md").read
      ).content

      expect(body).to include("지호 · 이해도")
    end

    it "[4] 협력성 변화 — '혼자' (4월) → '모둠 잘' (6월)" do
      seed_entry(id: "01CON0000000000000000D001",
        body: "수아가 쉬는 시간에 혼자 있는다.",
        created_at: "2026-04-08T09:00:00+09:00")
      seed_entry(id: "01CON0000000000000000D002",
        body: "수아가 모둠 잘 어울리고 사회자 역할을 잘 한다.",
        created_at: "2026-06-10T09:00:00+09:00")
      seed_student_with_mentions(name: "수아", entry_ids: %w[01CON0000000000000000D001 01CON0000000000000000D002])

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/contradictions/observations.md").read
      ).content

      expect(body).to include("수아 · 협력성")
    end

    it "[5] 후퇴 방향 — '적극' (4월) → '소극' (6월) → 후퇴 표시" do
      seed_entry(id: "01CON0000000000000000E001",
        body: "준호가 4월 초 발표 자원을 자주 했다.",
        created_at: "2026-04-05T09:00:00+09:00")
      seed_entry(id: "01CON0000000000000000E002",
        body: "준호가 최근 소극적이고 듣는 역할만 한다.",
        created_at: "2026-06-20T09:00:00+09:00")
      seed_student_with_mentions(name: "준호", entry_ids: %w[01CON0000000000000000E001 01CON0000000000000000E002])

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/contradictions/observations.md").read
      ).content

      expect(body).to include("준호 · 참여도")
      expect(body).to include("→ 후퇴")
      # 후퇴 = high(적극)가 먼저 → low(소극)가 나중
      expect(body).to include("2026-04-05 → 2026-06-20")
    end
  end

  describe "#call (결정적 모드) — 산출물 형식" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      seed_entry(id: "01CONFMT00000000000000A01",
        body: "민준이는 소극적이다.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01CONFMT00000000000000A02",
        body: "민준이가 적극적으로 발표한다.",
        created_at: "2026-05-05T09:00:00+09:00")
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CONFMT00000000000000A01 01CONFMT00000000000000A02])
    end

    it "Success(target Pathname) — vault/.sowing/synth/contradictions/observations.md 작성" do
      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/contradictions/observations.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 9키 + synth_target=contradictions:observations + synth_students 목록" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/contradictions/observations.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("contradictions:observations")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["synth_students"]).to include("민준")
      expect(fm["title"]).to eq("학생 묘사 변화 후보")
    end

    it "톤 — '모순' 대신 '변화·발견'. 위키링크 인용 보존" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/contradictions/observations.md").read
      ).content

      expect(body).to include("변화·발견")
      expect(body).to include("후보일 뿐")
      expect(body).to include("[[00_Inbox/01CONFMT00000000000000A01.md]]")
      expect(body).to include("[[00_Inbox/01CONFMT00000000000000A02.md]]")
    end
  end

  describe "#call — 가드 / 엣지" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:no_observations) — 학생 mention 0건" do
      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_observations)
    end

    it "Failure(:no_observations) — mention 있어도 변화 차원 매칭 0" do
      seed_entry(id: "01CONNONE000000000000A01",
        body: "민준이가 출석함.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01CONNONE000000000000A02",
        body: "민준이가 학교 옴.",
        created_at: "2026-05-05T09:00:00+09:00")
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CONNONE000000000000A01 01CONNONE000000000000A02])

      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
    end

    it "한 학생 mention < MIN_MENTIONS_PER_STUDENT — 분석 대상 제외 (변화 추적 불가)" do
      seed_entry(id: "01CONONLY000000000000A01",
        body: "민준이가 발표를 거의 안 한다.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CONONLY000000000000A01])

      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
    end

    it "여러 학생 동시 — 각각 독립적으로 변화 후보 생성" do
      seed_entry(id: "01CONMULTI0000000000A01",
        body: "민준이가 소극적이다.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01CONMULTI0000000000A02",
        body: "민준이가 적극적이 됐다.",
        created_at: "2026-05-05T09:00:00+09:00")
      seed_entry(id: "01CONMULTI0000000000B01",
        body: "서연이가 산만했다.",
        created_at: "2026-04-15T09:00:00+09:00")
      seed_entry(id: "01CONMULTI0000000000B02",
        body: "서연이가 집중했다.",
        created_at: "2026-06-10T09:00:00+09:00")
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CONMULTI0000000000A01 01CONMULTI0000000000A02])
      seed_student_with_mentions(name: "서연", entry_ids: %w[01CONMULTI0000000000B01 01CONMULTI0000000000B02])

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/contradictions/observations.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content

      expect(fm["synth_students"]).to include("민준", "서연")
      expect(body).to include("민준 · 참여도")
      expect(body).to include("서연 · 집중도")
      expect(fm["synth_source_count"]).to be >= 2
    end

    it "학생 이름이 본문에 없는 entry — 차원 매칭 X (이름 포함 문장만)" do
      # mention DB 에는 있지만 본문엔 학생 이름 없음 → 분석 제외
      seed_entry(id: "01CONNNAME0000000000A01",
        body: "수업에서 적극적인 분위기.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01CONNNAME0000000000A02",
        body: "오늘 소극적인 흐름.",
        created_at: "2026-05-05T09:00:00+09:00")
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CONNNAME0000000000A01 01CONNNAME0000000000A02])

      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure  # 본문에 "민준" 없음 → 매칭 0
    end

    it "vault 파일 누락 — graceful (raise 안 함)" do
      seed_entry(id: "01CONMISS00000000000A01",
        body: "민준이는 소극적이다.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01CONMISS00000000000A02",
        body: "민준이가 적극적이 됐다.",
        created_at: "2026-05-05T09:00:00+09:00")
      vault_dir.join("00_Inbox/01CONMISS00000000000A01.md").delete
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CONMISS00000000000A01 01CONMISS00000000000A02])

      expect {
        use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      }.not_to raise_error
    end

    it "멱등 — 같은 호출 재실행 시 atomic 덮어쓰기" do
      seed_entry(id: "01CONIDEM00000000000A01",
        body: "민준이는 소극적이다.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01CONIDEM00000000000A02",
        body: "민준이가 적극적이 됐다.",
        created_at: "2026-05-05T09:00:00+09:00")
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CONIDEM00000000000A01 01CONIDEM00000000000A02])

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      first = vault_dir.join(".sowing/synth/contradictions/observations.md").mtime
      sleep 0.01
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      second = vault_dir.join(".sowing/synth/contradictions/observations.md").mtime

      expect(second).to be >= first
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
          "### 민준 · 참여도\n- 변화 시점: 2026-04-12 → 2026-05-05\n- 인용 [#1] [#2]\n- 가능한 분기점: 협동학습 도입\n- 다음 관찰 제안: 한 달 더 추적\n"
        end

        def name
          "fake:contradiction-detector"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    before do
      seed_entry(id: "01CONLLM0000000000000A01",
        body: "민준이는 소극적이다.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01CONLLM0000000000000A02",
        body: "민준이가 적극적이 됐다.",
        created_at: "2026-05-05T09:00:00+09:00")
      seed_student_with_mentions(name: "민준", entry_ids: %w[01CONLLM0000000000000A01 01CONLLM0000000000000A02])
    end

    it "backend.chat 1회 호출 + LLM 출력 본문 반영" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(fake_backend.calls.size).to eq(1)
      content = vault_dir.join(".sowing/synth/contradictions/observations.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content

      expect(fm["synth_model"]).to eq("fake:contradiction-detector")
      expect(body).to include("협동학습 도입")
      expect(body).to include("다음 관찰 제안")
    end

    it "audit log actor=agent — LLM chat 동안" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end

      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(observed).to eq("agent")
    end

    it "LLM 실패 → 결정적 폴백" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")

      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/contradictions/observations.md").read
      ).content
      expect(body).to include("결정적 합성 (반의어 차원")
    end
  end
end
