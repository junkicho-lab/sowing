# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::ExtractTrainingApplications do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-training-spec-")) }
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

  def seed_training(id:, body:, created_at:, title: "협동학습 연수")
    path = "20_Notes/trainings/#{id}.md"
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    File.write(abs,
      "---\nid: #{id}\nmode: note\ncategory: trainings\ntitle: #{title}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\n---\n\n#{body}\n")

    db[:entries].insert(
      id: id, path: path, mode: "note", category: "trainings",
      title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: body.split.size, indexed_at: created_at
    )
  end

  def seed_followup(id:, body:, created_at:, mode: "memo", category: nil)
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

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    let(:training_id) { "01TRA000000000000000000A" }

    before do
      seed_training(id: training_id,
        body: "협동학습 연수 정리. 모둠 사회자 역할 분담. 차시별 보조과제 활용. 갈등 해결 시나리오 카드 도입. 또래 코칭 전략.",
        created_at: "2026-04-01T14:00:00+09:00", title: "협동학습 연수")

      # 적용 사례 — 연수 키워드(모둠/사회자/차시/갈등/카드/또래) 포함 entries
      seed_followup(id: "01TRAAPP00000000000000A1",
        body: "오늘 모둠 사회자 역할 도입. 잘 작동.",
        created_at: "2026-04-10T09:00:00+09:00", mode: "memo")
      seed_followup(id: "01TRAAPP00000000000000A2",
        body: "차시별 보조과제 카드 만들어 활용.",
        created_at: "2026-05-05T09:00:00+09:00", mode: "note", category: "lessons")
      seed_followup(id: "01TRAAPP00000000000000A3",
        body: "갈등 상황에서 카드 사용 — 효과적.",
        created_at: "2026-06-15T09:00:00+09:00", mode: "record", category: "수업회고")

      # 매칭 안 되는 entry — 키워드 0
      seed_followup(id: "01TRANOM00000000000000A1",
        body: "오늘 출석 점검만 함.",
        created_at: "2026-05-10T09:00:00+09:00", mode: "memo")
    end

    it "Success(target Pathname) — vault/.sowing/synth/trainings/{id}.md 작성" do
      result = use_case.call(training_id: training_id)
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/trainings/#{training_id}.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 11키 + synth_target=training:{id} + keywords/unmatched 추출" do
      use_case.call(training_id: training_id)
      content = vault_dir.join(".sowing/synth/trainings/#{training_id}.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("training:#{training_id}")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["synth_followup_days"]).to eq(90)
      expect(fm["synth_keywords"]).to be_an(Array)
      expect(fm["synth_keywords"]).not_to be_empty
      expect(fm["synth_unmatched_keywords"]).to be_an(Array)
      expect(fm["synth_training_path"]).to eq("20_Notes/trainings/#{training_id}.md")
      expect(fm["title"]).to include("연수 적용 추적")
    end

    it "키워드 추출 — '모둠'/'사회자'/'차시'/'카드' 등 본문 명사 포함" do
      use_case.call(training_id: training_id)
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{training_id}.md").read
      ).front_matter
      kws = fm["synth_keywords"].join(" ")
      # 연수 본문에 등장한 핵심 명사 (조사 제거 후) 가 포함됨
      expect(kws).to include("모둠")
    end

    it "적용 후보 — 연수 키워드 매칭 후속 entries 만 (3건), 매칭 안 되는 entry 제외" do
      use_case.call(training_id: training_id)
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{training_id}.md").read
      ).front_matter
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{training_id}.md").read
      ).content

      # 매칭 3건
      expect(fm["synth_source_count"]).to eq(3)
      expect(body).to include("[[00_Inbox/01TRAAPP00000000000000A1.md]]")
      expect(body).to include("[[20_Notes/lessons/01TRAAPP00000000000000A2.md]]")
      expect(body).to include("[[30_Records/2026/수업회고/01TRAAPP00000000000000A3.md]]")
      # 매칭 안 되는 entry 는 제외
      expect(body).not_to include("01TRANOM00000000000000A1")
    end

    it "D+N 적용 시점 표시 — 연수 후 며칠 차" do
      use_case.call(training_id: training_id)
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{training_id}.md").read
      ).content

      # 4월 10일 = 연수(4월 1일) + 9일 → D+9
      expect(body).to include("D+9일")
      # 5월 5일 = D+34
      expect(body).to include("D+34일")
      # 6월 15일 = D+75
      expect(body).to include("D+75일")
    end

    it "연수 원본 wikilink 본문 상단 + trailer 단정 거부 톤" do
      use_case.call(training_id: training_id)
      content = vault_dir.join(".sowing/synth/trainings/#{training_id}.md").read
      body = FrontMatterParser::Parser.new(:md).call(content).content

      expect(body).to include("원본 연수: [[20_Notes/trainings/#{training_id}.md]]")
      expect(body).to include("결정적 합성")
      expect(body).to include("*후보*")  # trailer "각 매칭은 *후보* 일 뿐"
    end
  end

  describe "#call — 시나리오 3종 (ROADMAP 검증)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "[1] 연수 후 즉시 적용 — D+1 entry 매칭" do
      tid = "01TRSCEN10000000000000A1"
      seed_training(id: tid, body: "프로젝트 학습 연수. 산출물 중심 평가.",
        created_at: "2026-05-01T09:00:00+09:00")
      seed_followup(id: "01TRSCEN10000000000000B1",
        body: "오늘 프로젝트 학습 시도 — 첫 시도.",
        created_at: "2026-05-02T09:00:00+09:00", mode: "memo")

      use_case.call(training_id: tid)
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).content
      expect(body).to include("D+1일")
      expect(body).to include("[[00_Inbox/01TRSCEN10000000000000B1.md]]")
    end

    it "[2] 한 달 후 적용 — D+30 entry 매칭 + 사이 미적용 정상" do
      tid = "01TRSCEN20000000000000A2"
      seed_training(id: tid, body: "토론 수업 연수. 4단계 토론 절차.",
        created_at: "2026-05-01T09:00:00+09:00")
      seed_followup(id: "01TRSCEN20000000000000B2",
        body: "토론 수업 첫 시도 — 4단계 절차 적용.",
        created_at: "2026-05-31T09:00:00+09:00", mode: "record", category: "수업회고")

      use_case.call(training_id: tid)
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).front_matter
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).content
      expect(fm["synth_source_count"]).to eq(1)
      expect(body).to include("D+30일")
    end

    it "[3] 미적용 — 후속 entries 0 + 매칭 0 → 안내 문구" do
      tid = "01TRSCEN30000000000000A3"
      seed_training(id: tid, body: "AI 활용 수업 연수. 챗봇 도입.",
        created_at: "2026-05-01T09:00:00+09:00")
      # 후속 entries 없음

      use_case.call(training_id: tid)
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).content
      expect(body).to include("키워드 매칭 entries 가 없습니다")
      # 미적용 키워드는 frontmatter 에
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).front_matter
      expect(fm["synth_unmatched_keywords"]).not_to be_empty
      expect(fm["synth_source_count"]).to eq(0)
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:training_not_found) — 존재하지 않는 entry id" do
      result = use_case.call(training_id: "01NOTEXIST00000000000000")
      expect(result).to be_failure
      expect(result.failure).to eq(:training_not_found)
    end

    it "Failure(:training_not_found) — entry 존재해도 category != trainings" do
      seed_followup(id: "01TRANTC00000000000000A1",
        body: "수업 메모 — trainings 아님.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "memo")
      result = use_case.call(training_id: "01TRANTC00000000000000A1")
      expect(result).to be_failure
      expect(result.failure).to eq(:training_not_found)
    end

    it "Failure(:no_keywords) — 본문이 너무 짧거나 한국어 명사 없음" do
      tid = "01TRANK0000000000000000A"
      seed_training(id: tid, body: "abc 123 ...", created_at: "2026-05-01T09:00:00+09:00")
      result = use_case.call(training_id: tid)
      expect(result).to be_failure
      expect(result.failure).to eq(:no_keywords)
    end

    it "Failure(:too_many_followups) — 후속 entries > MAX (가드)" do
      stub_const("Sowing::UseCases::ExtractTrainingApplications::MAX_FOLLOWUP_ENTRIES", 2)
      tid = "01TRAMAX0000000000000A01"
      seed_training(id: tid, body: "협동학습 모둠 활동 정리.",
        created_at: "2026-05-01T09:00:00+09:00")
      4.times do |i|
        seed_followup(id: "01TRAMAX0000000000000B0#{i + 1}",
          body: "후속 entry #{i}.",
          created_at: "2026-05-#{(i + 2).to_s.rjust(2, "0")}T09:00:00+09:00", mode: "memo")
      end
      result = use_case.call(training_id: tid)
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_followups)
    end

    it "followup_days 인자 — 90 → 30 으로 좁힘" do
      tid = "01TRADAYS00000000000000A"
      seed_training(id: tid, body: "협동학습 모둠 활동 정리.",
        created_at: "2026-05-01T09:00:00+09:00")
      seed_followup(id: "01TRADAYS00000000000000B",
        body: "모둠 활동 적용 — 60일 후.",
        created_at: "2026-06-30T09:00:00+09:00", mode: "memo")

      # 30일 추적 → 6/30 (D+60) 은 범위 밖
      use_case.call(training_id: tid, followup_days: 30)
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).front_matter
      expect(fm["synth_source_count"]).to eq(0)
      expect(fm["synth_followup_days"]).to eq(30)
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
          "## 📚 연수 핵심 요약\n협동학습.\n\n## ✨ 적용된 사례\n모둠 사회자 [1]\n\n## 🌱 미적용 영역\n또래 코칭 미시도\n\n## 💡 다음 적용 후보\n- 또래 코칭 1회\n"
        end

        def name
          "fake:training-applications"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    let(:tid) { "01TRALLM0000000000000A01" }

    before do
      seed_training(id: tid, body: "협동학습 모둠 사회자 또래 코칭.",
        created_at: "2026-04-01T09:00:00+09:00")
      seed_followup(id: "01TRALLM0000000000000B01",
        body: "모둠 사회자 도입.",
        created_at: "2026-04-15T09:00:00+09:00", mode: "memo")
    end

    it "backend.chat 1회 호출 + LLM 본문 반영" do
      use_case.call(training_id: tid)
      expect(fake_backend.calls.size).to eq(1)
      content = vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content
      expect(fm["synth_model"]).to eq("fake:training-applications")
      expect(body).to include("💡 다음 적용 후보")
    end

    it "audit log actor=agent — LLM chat 동안" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Infrastructure::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call(training_id: tid)
      expect(observed).to eq("agent")
    end

    it "LLM 실패 → 결정적 fallback" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(training_id: tid)
      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).content
      expect(body).to include("결정적 합성")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "멱등 — 같은 training_id 재호출 atomic 덮어쓰기" do
      tid = "01TRAIDEM0000000000000A1"
      seed_training(id: tid, body: "협동학습 모둠 활동.",
        created_at: "2026-04-01T09:00:00+09:00")

      use_case.call(training_id: tid)
      first = vault_dir.join(".sowing/synth/trainings/#{tid}.md").mtime
      sleep 0.01
      use_case.call(training_id: tid)
      second = vault_dir.join(".sowing/synth/trainings/#{tid}.md").mtime
      expect(second).to be >= first
    end

    it "vault 파일 누락 후속 entry → graceful skip" do
      tid = "01TRAMISS0000000000000A1"
      seed_training(id: tid, body: "협동학습 모둠 활동.",
        created_at: "2026-04-01T09:00:00+09:00")
      seed_followup(id: "01TRAMISS0000000000000B1",
        body: "모둠 활동 적용.",
        created_at: "2026-04-10T09:00:00+09:00", mode: "memo")
      vault_dir.join("00_Inbox/01TRAMISS0000000000000B1.md").delete

      expect { use_case.call(training_id: tid) }.not_to raise_error
    end

    it "한 entry 여러 키워드 매칭 → 1회만 카운트 (path 기준 dedupe)" do
      tid = "01TRADEDUP00000000000A01"
      seed_training(id: tid, body: "협동학습 모둠 사회자 차시 카드.",
        created_at: "2026-04-01T09:00:00+09:00")
      # 모둠 + 사회자 + 차시 + 카드 모두 포함하는 entry
      seed_followup(id: "01TRADEDUP00000000000B01",
        body: "모둠 사회자가 차시별 카드 사용.",
        created_at: "2026-04-10T09:00:00+09:00", mode: "memo")

      use_case.call(training_id: tid)
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).front_matter
      # 1건만 (multiple keywords 같은 entry 내)
      expect(fm["synth_source_count"]).to eq(1)
    end

    it "STOPWORDS 제외 — '오늘'/'학생' 등은 키워드 후보 아님" do
      tid = "01TRASW0000000000000000A"
      seed_training(id: tid,
        body: "오늘 학생들과 협동학습 모둠 활동 진행. 우리 학급 모두 참여.",
        created_at: "2026-04-01T09:00:00+09:00")
      use_case.call(training_id: tid)
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/trainings/#{tid}.md").read
      ).front_matter
      # 의미 키워드는 포함
      expect(fm["synth_keywords"]).to include("협동학습")
      # STOPWORDS 는 제외
      expect(fm["synth_keywords"]).not_to include("오늘", "학생", "학생들", "우리", "모두")
    end
  end
end
