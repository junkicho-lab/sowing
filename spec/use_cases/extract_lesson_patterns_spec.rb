# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::ExtractLessonPatterns do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-patterns-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 7, 31, 18, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  def seed_lesson(id:, body:, created_at:, category: "수업", title: "수업")
    path = "20_Notes/#{category}/#{id}.md"
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    File.write(abs, "---\nid: #{id}\nmode: note\ncategory: #{category}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\n---\n\n#{body}\n")

    db[:entries].insert(
      id: id, path: path, mode: "note",
      title: title, category: category,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: body.split.size, indexed_at: created_at
    )
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      seed_lesson(id: "01LP000000000000000000P01",
        body: "오늘 협동학습 첫 시도. 학생들 활기차게 참여했고 분위기 좋았다. 효과적인 차시.",
        created_at: "2026-04-02T09:00:00+09:00", title: "협동학습 1차시")
      seed_lesson(id: "01LP000000000000000000P02",
        body: "도덕 갈등 해결 활동. 학생들이 몰입했고 보람 있는 수업이었다.",
        created_at: "2026-04-15T09:00:00+09:00", title: "도덕 갈등 해결", category: "도덕")
      seed_lesson(id: "01LP000000000000000000N01",
        body: "분수 단원 어려웠다. 시간 부족했고 학생들 산만했다.",
        created_at: "2026-05-10T09:00:00+09:00", title: "분수 단원")
      seed_lesson(id: "01LP000000000000000000N02",
        body: "사회 토론 수업 아쉬웠음. 의도와 다르게 진행이 더디었다.",
        created_at: "2026-05-20T09:00:00+09:00", title: "사회 토론")
      seed_lesson(id: "01LP000000000000000000M01",
        body: "체육 줄넘기. 학생들 즐겁게 활동했다.",
        created_at: "2026-06-01T09:00:00+09:00", title: "줄넘기")
    end

    it "Success(target Pathname) — vault/.sowing/synth/patterns/lessons.md 작성" do
      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/patterns/lessons.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 9키 + synth_target=patterns:lessons + categories 포함" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/patterns/lessons.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("patterns:lessons")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["synth_categories"]).to include("수업", "도덕")
      expect(fm["title"]).to eq("수업 패턴 후보")
    end

    it "긍정 신호어 매칭 — '활기' '몰입' '보람' '효과적' 등 → 잘된 수업 섹션" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/patterns/lessons.md").read
      ).content

      expect(body).to include("✨ 잘된 수업")
      # 협동학습 + 도덕 두 entry 인용 (긍정 신호어 매칭된 문장의 출처 wikilink)
      expect(body).to include("[[20_Notes/수업/01LP000000000000000000P01.md]]")
      expect(body).to include("[[20_Notes/도덕/01LP000000000000000000P02.md]]")
      # 매칭된 핵심 키워드가 인용에 보존
      expect(body).to include("활기")
      expect(body).to include("몰입")
    end

    it "부정 신호어 매칭 — '어려웠' '아쉬웠' '산만' '진행이 더디' → 아쉬웠던 수업 섹션" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/patterns/lessons.md").read
      ).content

      expect(body).to include("🌱 아쉬웠던 수업")
      expect(body).to include("[[20_Notes/수업/01LP000000000000000000N01.md]]")
      expect(body).to include("[[20_Notes/수업/01LP000000000000000000N02.md]]")
    end

    it "부정 표현 5자 윈도 — '잘 안 됐다' 는 긍정 매칭 무효화" do
      # 외부 before 의 5건 + 본 case 의 새 entry → MIN_ENTRIES 충족
      seed_lesson(id: "01LPNEGATIONTEST000000001",
        body: "오늘 협동학습 잘 안 됐다. 학생들 산만했고 효과적이지 못했다.",
        created_at: "2026-06-15T09:00:00+09:00", title: "협동학습 실패")
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/patterns/lessons.md").read
      ).content

      # "잘 안 됐다" 의 "잘"은 부정 윈도(앞 0자 + 뒤 5자 = " 안 됐다") 안에 "안" → 무효
      # → NEGATIONTEST 파일이 *잘된 수업 섹션* 안에 인용되면 안 됨 (다음 ## 까지만 검사)
      success_section = body[/## ✨ 잘된 수업[\s\S]*?(?=^## )/m]
      expect(success_section).not_to include("01LPNEGATIONTEST000000001")
      # 부정은 매칭됨 (산만) → 아쉬웠던 섹션에 등장
      expect(body).to include("🌱 아쉬웠던 수업")
      expect(body).to include("[[20_Notes/수업/01LPNEGATIONTEST000000001.md]]")
    end

    it "결정적 trailer 문구 + 정직성 (단정 안 함, 후보일 뿐)" do
      use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/patterns/lessons.md").read
      ).content

      expect(body).to include("결정적 합성")
      expect(body).to include("후보일 뿐")
    end
  end

  describe "#call — 카테고리 / 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "기본 카테고리 — 수업/수업회고/lessons/도덕/도덕수업" do
      seed_lesson(id: "01LPDEFAULT000000000000A1", body: "성공적인 수업.",
        created_at: "2026-05-10T09:00:00+09:00", category: "수업")
      seed_lesson(id: "01LPDEFAULT000000000000A2", body: "보람 있는 lessons.",
        created_at: "2026-05-15T09:00:00+09:00", category: "lessons")
      seed_lesson(id: "01LPDEFAULT000000000000A3", body: "도덕 효과적.",
        created_at: "2026-05-20T09:00:00+09:00", category: "도덕")
      # 비-수업 카테고리 (회의 등) 는 입력에서 제외됨
      seed_lesson(id: "01LPDEFAULT000000000000Z1", body: "회의 어려웠다.",
        created_at: "2026-05-25T09:00:00+09:00", category: "회의")

      result = use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_success

      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/patterns/lessons.md").read
      ).content
      # 회의는 분석 대상 아님
      expect(body).not_to include("[[20_Notes/회의/")
    end

    it "사용자 정의 카테고리 — categories: 명시" do
      seed_lesson(id: "01LPCUSTOM00000000000001A", body: "프로젝트 학습 성공.",
        created_at: "2026-05-10T09:00:00+09:00", category: "프로젝트")
      seed_lesson(id: "01LPCUSTOM00000000000001B", body: "프로젝트 학습 효과적.",
        created_at: "2026-05-15T09:00:00+09:00", category: "프로젝트")
      seed_lesson(id: "01LPCUSTOM00000000000001C", body: "프로젝트 학습 보람.",
        created_at: "2026-05-20T09:00:00+09:00", category: "프로젝트")

      result = use_case.call(categories: ["프로젝트"],
        since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_success
      content = vault_dir.join(".sowing/synth/patterns/lessons.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      expect(fm["synth_categories"]).to eq(["프로젝트"])
    end

    it "Failure(:no_entries) — 카테고리 매칭 entries < MIN_ENTRIES (3건)" do
      seed_lesson(id: "01LPNOENT000000000000001", body: "수업 1.",
        created_at: "2026-05-10T09:00:00+09:00")
      result = use_case.call(since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end

    it "Failure(:too_many_entries) — entries > MAX (가드)" do
      stub_const("Sowing::UseCases::ExtractLessonPatterns::MAX_ENTRIES", 2)
      4.times do |i|
        seed_lesson(id: "01LPMANY00000000000000#{i + 1}", body: "수업 #{i}",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00")
      end
      result = use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
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
          "## ✨ 잘된 수업 — 공통점 후보\n- 학생 능동성 [1]\n- 활동 중심 [2]\n\n## 🌱 아쉬웠던 수업 — 공통점 후보\n- 시간 부족 [1]\n\n## 💡 다음 수업에 시도할 만한 것\n- 차시별 보조 과제 카드\n"
        end

        def name
          "fake:lesson-patterns"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    before do
      seed_lesson(id: "01LPLLM00000000000000001A", body: "협동학습 활기. 효과적.",
        created_at: "2026-05-05T09:00:00+09:00")
      seed_lesson(id: "01LPLLM00000000000000001B", body: "토론 수업 어려웠다. 시간 부족.",
        created_at: "2026-05-10T09:00:00+09:00")
      seed_lesson(id: "01LPLLM00000000000000001C", body: "도덕 보람 있었다.",
        created_at: "2026-05-15T09:00:00+09:00", category: "도덕")
    end

    it "backend.chat 1회 호출 (단일 종합 prompt — 청크 분할 X)" do
      use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(fake_backend.calls.size).to eq(1)
    end

    it "synth_model = backend.name + LLM 출력 본문 반영 + 다음 시도 섹션" do
      use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/patterns/lessons.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content

      expect(fm["synth_model"]).to eq("fake:lesson-patterns")
      expect(body).to include("💡 다음 수업에 시도할 만한 것")
      expect(body).to include("차시별 보조 과제 카드")
    end

    it "audit log actor=agent — LLM chat 동안" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end

      use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(observed).to eq("agent")
    end

    it "LLM 실패 → 결정적 폴백" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")

      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/patterns/lessons.md").read
      ).content
      expect(body).to include("결정적 합성")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "긍정/부정 신호어 모두 0 — 빈 후보 안내" do
      seed_lesson(id: "01LPNEUTRAL00000000000001", body: "수업 진행함.",
        created_at: "2026-05-10T09:00:00+09:00")
      seed_lesson(id: "01LPNEUTRAL00000000000002", body: "수업 끝남.",
        created_at: "2026-05-15T09:00:00+09:00")
      seed_lesson(id: "01LPNEUTRAL00000000000003", body: "수업 진행함.",
        created_at: "2026-05-20T09:00:00+09:00")

      result = use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/patterns/lessons.md").read
      ).content
      expect(body).to include("긍정 신호어 매칭 없음")
      expect(body).to include("부정 신호어 매칭 없음")
    end

    it "멱등 — 같은 호출 재실행 시 atomic 덮어쓰기" do
      3.times do |i|
        seed_lesson(id: "01LPIDEM000000000000000#{i + 1}", body: "수업 활기.",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00")
      end

      use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      first = vault_dir.join(".sowing/synth/patterns/lessons.md").mtime
      sleep 0.01
      use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      second = vault_dir.join(".sowing/synth/patterns/lessons.md").mtime

      expect(second).to be >= first
    end

    it "vault 파일 누락 entry — graceful (빈 body, raise 안 함)" do
      seed_lesson(id: "01LPMISS0000000000000001A", body: "수업 활기.",
        created_at: "2026-05-10T09:00:00+09:00")
      vault_dir.join("20_Notes/수업/01LPMISS0000000000000001A.md").delete
      seed_lesson(id: "01LPMISS0000000000000001B", body: "수업 효과적.",
        created_at: "2026-05-15T09:00:00+09:00")
      seed_lesson(id: "01LPMISS0000000000000001C", body: "수업 보람.",
        created_at: "2026-05-20T09:00:00+09:00")

      expect {
        use_case.call(since: "2026-05-01T00:00:00+09:00", until_time: "2026-05-31T23:59:59+09:00")
      }.not_to raise_error
    end
  end
end
