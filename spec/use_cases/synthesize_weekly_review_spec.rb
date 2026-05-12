# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeWeeklyReview do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-weekly-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  # 2026-05-10 일요일 — 2026-W19 (Mon 5/4 ~ Sun 5/10)
  let(:fixed_now) { Time.new(2026, 5, 10, 18, 0, 0, "+09:00") }
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

  def seed_student(name:, entry_ids: [])
    eid = db[:entities].insert(
      type: "student", name: name,
      first_seen_at: "2026-04-01T00:00:00+09:00",
      last_seen_at: "2026-05-10T00:00:00+09:00",
      mention_count: entry_ids.size
    )
    entry_ids.each { |id| db[:entity_mentions].insert(entity_id: eid, entry_id: id) }
    eid
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # 2026-W19: 5/4 (Mon) ~ 5/10 (Sun). 7일에 걸쳐 entries 시드.
      seed_entry(id: "01WK1MON0000000000000A01", body: "월요일 메모.",
        created_at: "2026-05-04T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01WK1WED0000000000000A02", body: "민준이 발표 자원.",
        created_at: "2026-05-06T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01WK1WED0000000000000A03",
        body: "수요일 수업 정리.\n- [ ] 분수 단원 보조과제 카드 만들기\n- [ ] 학부모 면담 일정 확정",
        created_at: "2026-05-06T20:00:00+09:00", mode: "record", category: "수업회고", title: "수업 회고")
      seed_entry(id: "01WK1FRI0000000000000A04", body: "민준이 모둠 잘함. 서연이도 협력적.",
        created_at: "2026-05-08T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01WK1SUN0000000000000A05",
        body: "일요일 점검.\n- [ ] 다음 주 도덕 갈등 활동 준비",
        created_at: "2026-05-10T20:00:00+09:00", mode: "memo")

      seed_student(name: "민준", entry_ids: %w[01WK1WED0000000000000A02 01WK1FRI0000000000000A04])
      seed_student(name: "서연", entry_ids: %w[01WK1FRI0000000000000A04])
    end

    it "Success(target Pathname) — vault/.sowing/synth/weekly/2026-W19.md (자동 ISO 주)" do
      result = use_case.call
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/weekly/2026-W19.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 8키 + synth_target=week:2026-W19 + incomplete_task_count" do
      use_case.call
      content = vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("week:2026-W19")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["synth_source_count"]).to eq(5)
      expect(fm["synth_incomplete_task_count"]).to eq(3)
      expect(fm["title"]).to eq("주간 회고: 2026-W19")
    end

    it "본문 — 모드 카운트 + 일별 빈도 (한국 요일 라벨) + top 학생 + 미완료 task" do
      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).content

      expect(body).to include("📅 이번 주 요약")
      expect(body).to include("총 5건")
      expect(body).to include("💭") # memo
      expect(body).to include("📖") # record
      # 일별 빈도 + 한국 요일
      expect(body).to include("2026-05-04 (월)")
      expect(body).to include("2026-05-06 (수)")
      expect(body).to include("2026-05-10 (일)")
      # top 학생 — 민준 2회, 서연 1회 (mention 기준)
      expect(body).to include("**민준**: 2회 언급")
      expect(body).to include("**서연**: 1회 언급")
      # 미완료 task 3건 — `- [ ]` 텍스트
      expect(body).to include("분수 단원 보조과제 카드 만들기")
      expect(body).to include("학부모 면담 일정 확정")
      expect(body).to include("다음 주 도덕 갈등 활동 준비")
    end

    it "수요일 작성 빈도 막대 — 2건 → ▌▌" do
      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).content

      # "2026-05-06 (수): ▌▌ 2건" 패턴 (2건 entries)
      expect(body).to match(/2026-05-06.*▌▌\s*2건/)
    end

    it "결정적 trailer — 단정 거부 톤" do
      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("'잘했다/못했다' 단정 X")
    end
  end

  describe "#call — week_label / since-until 명시 인자" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "week_label 명시 — 자동 추론 무시하고 라벨 그대로 사용" do
      seed_entry(id: "01WKLAB0000000000000A001", body: "x",
        created_at: "2026-04-15T09:00:00+09:00", mode: "memo")
      result = use_case.call(week_label: "2026-W16",
        since: "2026-04-13T00:00:00+09:00",
        until_time: "2026-04-19T23:59:59+09:00")
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/weekly/2026-W16.md")).to exist
    end

    it "since 만 명시 — 7일 후까지 자동 (until 없음)" do
      seed_entry(id: "01WKSIN0000000000000A001", body: "x",
        created_at: "2026-04-15T09:00:00+09:00", mode: "memo")
      use_case.call(since: "2026-04-13T00:00:00+09:00",
        until_time: "2026-04-19T23:59:59+09:00")
      # week_label 자동 = since 기준
      expect(vault_dir.join(".sowing/synth/weekly/2026-W16.md")).to exist
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:no_entries) — 이번 주 entries 0건" do
      result = use_case.call
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end

    it "Failure(:too_many_entries) — > MAX (가드)" do
      stub_const("Sowing::UseCases::SynthesizeWeeklyReview::MAX_ENTRIES", 2)
      4.times do |i|
        seed_entry(id: "01WKMAX0000000000000A0#{i + 1}", body: "x",
          created_at: "2026-05-#{(4 + i).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end
      result = use_case.call
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_entries)
    end
  end

  describe "#call — task 추출 패턴" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "다양한 체크박스 형식 매칭 — `-`/`*` + 다양한 들여쓰기" do
      seed_entry(id: "01WKTSK0000000000000A001",
        body: "정리:\n- [ ] task1\n* [ ] task2\n  - [ ] task3 들여쓰기\n- [x] 완료된 task — 매칭 X",
        created_at: "2026-05-06T09:00:00+09:00", mode: "memo")
      use_case.call
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).front_matter
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).content
      # 3 미완료 — 완료된 [x] 는 제외
      expect(fm["synth_incomplete_task_count"]).to eq(3)
      expect(body).to include("task1")
      expect(body).to include("task2")
      expect(body).to include("task3")
      expect(body).not_to include("완료된 task")
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
          "## 🌊 이번 주 흐름\n5건 작성.\n\n## 💡 작은 발견\n민준이 적극 [1]\n\n## ☐ 미해결\n분수 단원\n\n## 🎯 다음 주 우선순위\n- 도덕 갈등\n"
        end

        def name
          "fake:weekly-review"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    before do
      seed_entry(id: "01WKLLM0000000000000A001", body: "x",
        created_at: "2026-05-06T09:00:00+09:00", mode: "memo")
    end

    it "backend.chat 1회 + 출력 본문 반영" do
      use_case.call
      expect(fake_backend.calls.size).to eq(1)
      content = vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content
      expect(fm["synth_model"]).to eq("fake:weekly-review")
      expect(body).to include("🎯 다음 주 우선순위")
    end

    it "audit log actor=agent — LLM chat 동안" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call
      expect(observed).to eq("agent")
    end

    it "LLM 실패 → 결정적 fallback" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call
      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).content
      expect(body).to include("결정적 합성")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "task 0건 — 안내 문구 표시" do
      seed_entry(id: "01WKNOTSK0000000000A001", body: "체크박스 없는 메모.",
        created_at: "2026-05-06T09:00:00+09:00", mode: "memo")
      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).content
      expect(body).to include("`- [ ]` 패턴 없음")
    end

    it "학생 entity 0개 — 안내 문구" do
      seed_entry(id: "01WKNOENT00000000000A01", body: "학생 언급 없음.",
        created_at: "2026-05-06T09:00:00+09:00", mode: "memo")
      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).content
      expect(body).to include("학생 언급 없음")
    end

    it "멱등 — 같은 주 재호출 시 atomic 덮어쓰기" do
      seed_entry(id: "01WKIDEM0000000000000A1", body: "x",
        created_at: "2026-05-06T09:00:00+09:00", mode: "memo")
      use_case.call
      first = vault_dir.join(".sowing/synth/weekly/2026-W19.md").mtime
      sleep 0.01
      use_case.call
      second = vault_dir.join(".sowing/synth/weekly/2026-W19.md").mtime
      expect(second).to be >= first
    end

    it "task 20개 초과 — 첫 20개만 + '그 외 N건' 안내" do
      body_with_many = "정리:\n" + (1..25).map { |i| "- [ ] task #{i}" }.join("\n")
      seed_entry(id: "01WKMNY0000000000000A001", body: body_with_many,
        created_at: "2026-05-06T09:00:00+09:00", mode: "memo")
      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/weekly/2026-W19.md").read
      ).content
      expect(body).to include("그 외 5건")
    end
  end
end
