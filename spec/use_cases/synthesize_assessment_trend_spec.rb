# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeAssessmentTrend do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-assessment-spec-")) }
  let(:db) { Sowing::Infrastructure::DB.connection }
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

  def seed_entry(id:, body:, created_at:, mode: "memo", category: nil)
    path = case mode
    when "memo" then "00_Inbox/#{id}.md"
    when "note" then "20_Notes/#{category || "lessons"}/#{id}.md"
    when "record" then "30_Records/#{Time.iso8601(created_at).year}/#{category || "수업회고"}/#{id}.md"
    end
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    fm = "id: #{id}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'"
    fm += "\ncategory: #{category}" if category
    File.write(abs, "---\n#{fm}\n---\n\n#{body}\n")

    db[:entries].insert(
      id: id, path: path, mode: mode, category: category,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: body.split.size, indexed_at: created_at
    )
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
      # 단원평가 4건 시드 — 강점 (분수, 곱셈) + 약점 (도형, 통분) 시나리오
      seed_entry(id: "01ATR000000000000000A001",
        body: "민준이는 분수 단원 평가에서 또래 이상으로 정확하게 풀었다.",
        created_at: "2026-04-15T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(id: "01ATR000000000000000A002",
        body: "민준이가 도형 단원평가를 어려워했다. 보강이 필요해 보임.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01ATR000000000000000A003",
        body: "민준이는 곱셈 수행평가에서 또박또박 풀이를 잘 설명했다.",
        created_at: "2026-06-05T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(id: "01ATR000000000000000A004",
        body: "민준이가 통분 단원에서 헷갈려 했다. 더 연습이 필요.",
        created_at: "2026-06-25T09:00:00+09:00", mode: "memo")

      seed_student(name: "민준",
        entry_ids: %w[01ATR000000000000000A001 01ATR000000000000000A002 01ATR000000000000000A003 01ATR000000000000000A004])
    end

    it "Success(target Pathname) — vault/.sowing/synth/assessments/민준.md 작성" do
      result = use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/assessments/민준.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 11키 + synth_target=assessment:민준 + units 추출 + strength/weakness 카운트" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/assessments/민준.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("assessment:민준")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["synth_categories"]).to include("평가")
      expect(fm["synth_units"]).to be_an(Array)
      expect(fm["synth_units"]).not_to be_empty
      expect(fm["synth_strength_count"]).to be >= 1
      expect(fm["synth_weakness_count"]).to be >= 1
      expect(fm["title"]).to eq("평가 추이: 민준")
    end

    it "본문 — 시간순 timeline + 강점/약점 섹션 + wikilink 인용" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/assessments/민준.md").read
      ).content

      expect(body).to include("📊 단원별 평가 결과")
      expect(body).to include("💪 잘한 단원")
      expect(body).to include("🌱 보강이 필요한 단원")
      # wikilink 인용
      expect(body).to include("[[30_Records/2026/평가/01ATR000000000000000A001.md]]")
      expect(body).to include("[[00_Inbox/01ATR000000000000000A002.md]]")
    end

    it "단원 라벨 추출 — '분수 단원' / '도형 단원평가' / '곱셈 수행평가' / '통분 단원'" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/assessments/민준.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content

      # 단원명 키워드가 본문 timeline 헤더에 포함
      expect(body).to match(/2026-04-15.*분수/)
      expect(body).to match(/2026-05-10.*도형/)
      # frontmatter units 에도 등장
      expect(fm["synth_units"].join(" ")).to include("분수")
      expect(fm["synth_units"].join(" ")).to include("도형")
    end

    it "강점/약점 분류 정확 — 부정 윈도 5자 필터 적용" do
      # "잘 못 풀었다" 같은 표현은 강점 매칭 X
      seed_entry(id: "01ATRNEG00000000000000A1",
        body: "민준이가 분수 단원평가에서 잘 못 풀었다.",
        created_at: "2026-07-10T09:00:00+09:00", mode: "memo")
      eid = db[:entities].where(type: "student", name: "민준").first[:id]
      db[:entity_mentions].insert(entity_id: eid, entry_id: "01ATRNEG00000000000000A1")

      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/assessments/민준.md").read
      ).content

      # 강점 섹션에 NEG 파일이 들어가면 안 됨 ("잘"이 부정 윈도 안)
      strength_section = body[/## 💪 잘한 단원[\s\S]*?(?=^## )/m]
      expect(strength_section).not_to include("01ATRNEG00000000000000A1")
    end

    it "결정적 trailer — 단정 거부 톤 ('후보일 뿐')" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/assessments/민준.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("학생 능력 단정 X")
    end
  end

  describe "#call — 입력 필터링" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "학생 이름 + 평가 키워드 둘 다 만족해야 입력 — 한쪽만 있으면 제외" do
      seed_student(name: "민준", entry_ids: [])
      # 학생 이름은 있지만 평가 키워드 없음 — 제외
      seed_entry(id: "01ATRFLT0000000000000A1",
        body: "민준이 발표 잘함.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "memo")
      # 평가 키워드 있지만 학생 이름 없음 — 제외
      seed_entry(id: "01ATRFLT0000000000000A2",
        body: "분수 단원 전체 평가.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "평가")
      # 둘 다 만족 — 포함 (2건 필요)
      seed_entry(id: "01ATRFLT0000000000000A3",
        body: "민준이 단원평가 잘 풀었다.",
        created_at: "2026-05-20T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(id: "01ATRFLT0000000000000A4",
        body: "민준 수행평가 우수.",
        created_at: "2026-05-25T09:00:00+09:00", mode: "record", category: "평가")

      result = use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/assessments/민준.md").read
      ).front_matter
      expect(fm["synth_source_count"]).to eq(2)
    end

    it "사용자 정의 categories override — 단원시험 같은 학교별 명칭" do
      seed_student(name: "민준", entry_ids: [])
      seed_entry(id: "01ATRCAT0000000000000A1",
        body: "민준이 단원시험 잘 풀었다.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "단원시험")
      seed_entry(id: "01ATRCAT0000000000000A2",
        body: "민준이 단원시험 우수.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "단원시험")

      result = use_case.call(student_name: "민준",
        categories: ["단원시험"],
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/assessments/민준.md").read
      ).front_matter
      expect(fm["synth_categories"]).to eq(["단원시험"])
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:entity_not_found) — 학생 entity 없음" do
      result = use_case.call(student_name: "없는학생")
      expect(result).to be_failure
      expect(result.failure).to eq(:entity_not_found)
    end

    it "Failure(:no_entries) — 매칭 < MIN_ENTRIES (2건)" do
      seed_student(name: "민준", entry_ids: [])
      seed_entry(id: "01ATRMIN000000000000A01",
        body: "민준 분수 단원평가.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "평가")

      result = use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end

    it "Failure(:too_many_entries) — entries > MAX (가드)" do
      stub_const("Sowing::UseCases::SynthesizeAssessmentTrend::MAX_ENTRIES", 2)
      seed_student(name: "민준", entry_ids: [])
      4.times do |i|
        seed_entry(id: "01ATRMAX000000000000A0#{i + 1}",
          body: "민준 #{i} 단원평가.",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          mode: "record", category: "평가")
      end
      result = use_case.call(student_name: "민준",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_entries)
    end

    it "since/until 기본 6개월 window" do
      seed_student(name: "민준", entry_ids: [])
      # fixed_now = 2026-07-31. 6개월 전 ~ 2026-02-01
      seed_entry(id: "01ATRDEF000000000000A01",
        body: "민준 분수 단원 (1월, 범위 밖).",
        created_at: "2026-01-15T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(id: "01ATRDEF000000000000A02",
        body: "민준 곱셈 단원 (5월).",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(id: "01ATRDEF000000000000A03",
        body: "민준 도형 단원 (6월).",
        created_at: "2026-06-15T09:00:00+09:00", mode: "record", category: "평가")

      result = use_case.call(student_name: "민준")
      expect(result).to be_success
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/assessments/민준.md").read
      ).front_matter
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
          "## 📊 단원별 평가 추이\n시간순 흐름.\n\n## 💪 강점 단원 (관찰)\n분수 [1]\n\n## 🌱 보강이 필요한 단원 (관찰)\n도형 [2]\n\n## 📚 다음 학습 우선순위 (제안)\n- 도형 보강 1회\n"
        end

        def name
          "fake:assessment-trend"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    before do
      seed_entry(id: "01ATRLLM000000000000A01",
        body: "민준 분수 단원 잘함.",
        created_at: "2026-04-10T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(id: "01ATRLLM000000000000A02",
        body: "민준 도형 단원평가 어려워.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "memo")
      seed_student(name: "민준",
        entry_ids: %w[01ATRLLM000000000000A01 01ATRLLM000000000000A02])
    end

    it "backend.chat 1회 호출 + LLM 본문 반영" do
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(fake_backend.calls.size).to eq(1)
      content = vault_dir.join(".sowing/synth/assessments/민준.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content
      expect(fm["synth_model"]).to eq("fake:assessment-trend")
      expect(body).to include("📚 다음 학습 우선순위")
    end

    it "audit log actor=agent — LLM chat 동안" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Infrastructure::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(observed).to eq("agent")
    end

    it "LLM 실패 → 결정적 fallback" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(student_name: "민준",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/assessments/민준.md").read
      ).content
      expect(body).to include("결정적 합성")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "멱등 — 같은 학생 재호출 atomic 덮어쓰기" do
      seed_student(name: "민준", entry_ids: [])
      2.times do |i|
        seed_entry(id: "01ATRIDEM00000000000A0#{i + 1}",
          body: "민준 단원평가 #{i}.",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          mode: "record", category: "평가")
      end
      use_case.call(student_name: "민준",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      first = vault_dir.join(".sowing/synth/assessments/민준.md").mtime
      sleep 0.01
      use_case.call(student_name: "민준",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      second = vault_dir.join(".sowing/synth/assessments/민준.md").mtime
      expect(second).to be >= first
    end

    it "vault 파일 누락 entry → graceful skip" do
      seed_student(name: "민준", entry_ids: [])
      seed_entry(id: "01ATRMISS00000000000A01",
        body: "민준 단원평가 1.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(id: "01ATRMISS00000000000A02",
        body: "민준 단원평가 2.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "평가")
      vault_dir.join("30_Records/2026/평가/01ATRMISS00000000000A01.md").delete

      expect {
        use_case.call(student_name: "민준",
          since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      }.not_to raise_error
    end

    it "강점·약점 둘 다 0 — 안내 문구 표시" do
      seed_student(name: "민준", entry_ids: [])
      seed_entry(id: "01ATRNEU00000000000A001",
        body: "민준 분수 단원평가 진행.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(id: "01ATRNEU00000000000A002",
        body: "민준 도형 단원평가 끝남.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "record", category: "평가")

      use_case.call(student_name: "민준",
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/assessments/민준.md").read
      ).content
      expect(body).to include("긍정 신호어 매칭 없음")
      expect(body).to include("부정 신호어 매칭 없음")
    end
  end
end
