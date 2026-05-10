# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "json"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeStudentDigest do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-digest-spec-")) }
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:fixed_now) { Time.new(2026, 5, 10, 14, 0, 0, "+09:00") }
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

  # 테스트용 entry + 마크다운 파일 + entity mention 일괄 시드.
  def seed_entry(id:, body:, created_at:, mode: "memo", path: nil)
    path ||= "00_Inbox/#{id}.md"
    abs_path = vault_dir.join(path)
    FileUtils.mkdir_p(abs_path.dirname)
    File.write(abs_path, "---\nid: #{id}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\n---\n\n#{body}\n")

    db[:entries].insert(
      id: id, path: path, mode: mode, created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: body.split.size, indexed_at: created_at
    )
  end

  def seed_entity(name:, type: "student")
    db[:entities].insert(
      type: type, name: name,
      first_seen_at: "2026-04-01T00:00:00+09:00",
      last_seen_at: "2026-05-10T00:00:00+09:00",
      mention_count: 0
    )
  end

  def seed_mention(entity_id:, entry_id:)
    db[:entity_mentions].insert(entity_id: entity_id, entry_id: entry_id)
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, clock: clock)
    }

    before do
      # dig-001 시드 시뮬레이션 — 민준 학생의 4건 entries 시간순.
      seed_entry(id: "01ENTRY00000000000000000A1",
        body: "민준이는 발표를 거의 안 한다. 시선도 잘 마주치지 않음.",
        created_at: "2026-04-12T09:00:00+09:00")
      seed_entry(id: "01ENTRY00000000000000000A2",
        body: "민준이가 오늘 처음으로 발표를 자원했다! 협동학습 모둠 사회자 역할 이후 변화.",
        created_at: "2026-05-05T14:30:00+09:00")
      seed_entry(id: "01ENTRY00000000000000000A3",
        body: "민준이는 1:1 대면보다 다대다(모둠)에서 편안해함. 모둠이 안전감을 주는 듯.",
        created_at: "2026-05-08T20:00:00+09:00", mode: "record",
        path: "30_Records/2026/학생기록/민준.md")
      seed_entry(id: "01ENTRY00000000000000000A4",
        body: "수학 분수 통분 단원 평가에서 민준이는 풀이 과정을 또래 평균 이상으로 잘 설명.",
        created_at: "2026-05-15T09:00:00+09:00")

      entity_id = seed_entity(name: "민준")
      4.times { |i| seed_mention(entity_id: entity_id, entry_id: "01ENTRY00000000000000000A#{i + 1}") }
    end

    it "민준 디제스트 → vault/.sowing/synth/students/민준.md 작성" do
      result = use_case.call(student_name: "민준")
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/students/민준.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 필수 키 5종 (is_synth/synth_target/synth_at/synth_source_count/synth_model)" do
      use_case.call(student_name: "민준")
      content = vault_dir.join(".sowing/synth/students/민준.md").read
      parsed = FrontMatterParser::Parser.new(:md).call(content)
      fm = parsed.front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("student:민준")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_source_count"]).to eq(4)
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["title"]).to eq("학생 관찰: 민준")
    end

    it "본문에 4건 entries 모두 인용 + 시간순 정렬 + 출처 [[path]] 위키링크" do
      use_case.call(student_name: "민준")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/students/민준.md").read
      ).content

      expect(body).to include("4건, 시간순")
      # 모든 entry path 가 위키링크로 인용
      expect(body).to include("[[00_Inbox/01ENTRY00000000000000000A1.md]]")
      expect(body).to include("[[00_Inbox/01ENTRY00000000000000000A2.md]]")
      expect(body).to include("[[30_Records/2026/학생기록/민준.md]]")
      # mode 아이콘
      expect(body).to include("💭") # memo
      expect(body).to include("📖") # record
      # 시간순 순서 — 4월 entry 가 5월 entry 앞에
      a1_idx = body.index("01ENTRY00000000000000000A1")
      a2_idx = body.index("01ENTRY00000000000000000A2")
      expect(a1_idx).to be < a2_idx
    end

    it "본문 발췌 — 학생 이름 등장 문장만" do
      use_case.call(student_name: "민준")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/students/민준.md").read
      ).content
      # 첫 entry: "민준이는 발표를 거의 안 한다" 가 인용에 포함
      expect(body).to include("발표를 거의 안 한다")
    end
  end

  describe "#call (LLM 모드)" do
    let(:fake_response) {
      <<~TXT
        ## 변화 요약 (시간 흐름)
        4월에는 발표 전무 [1]. 5월 초 첫 자원 발표 [2] — 협동학습 도입이 분기점.

        ## 주요 관찰
        - 모둠 환경에서 안전감 [3]
        - 절차적 사고 강함 [4]

        ## 후속 과제
        - 발표 기회 의도적 제공
        - 수학 강점 활용 학습 설계
      TXT
    }
    let(:fake_backend) {
      Sowing::Eval::Backends::FakeBackend.new(responses: [fake_response])
    }
    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock)
    }

    before do
      seed_entry(id: "01ENT00000000000000000B1",
        body: "민준이가 발표를 자원했다.",
        created_at: "2026-05-05T14:00:00+09:00")
      entity_id = seed_entity(name: "민준")
      seed_mention(entity_id: entity_id, entry_id: "01ENT00000000000000000B1")
    end

    it "LLM 응답 그대로 본문 사용 + synth_model=FakeBackend" do
      result = use_case.call(student_name: "민준")
      expect(result).to be_success

      content = vault_dir.join(".sowing/synth/students/민준.md").read
      parsed = FrontMatterParser::Parser.new(:md).call(content)
      expect(parsed.front_matter["synth_model"]).to eq("FakeBackend")
      expect(parsed.content).to include("변화 요약")
      expect(parsed.content).to include("협동학습 도입이 분기점")
    end

    it "LLM prompt 가 한국어 + 인용 출처 표기 안내 포함" do
      use_case.call(student_name: "민준")
      captured = fake_backend.captured_prompts.first
      expect(captured[:system]).to include("학생 관찰", "출처 인용", "추측")
      expect(captured[:user]).to include("민준")
      expect(captured[:user]).to include("[1]") # 인용 번호
    end

    it "LLM 호출 시 actor=agent (with_actor 통합)" do
      captured_actor = nil
      capturing_backend = Class.new(Sowing::Eval::Backends::Base) do
        define_method(:chat) do |system:, user:|
          captured_actor = Sowing::Infrastructure::AuditLog.current_actor
          "## 변화 요약\n테스트 응답"
        end
      end

      uc = described_class.new(db: db, vault_dir: vault_dir,
        llm_backend: capturing_backend.new, clock: clock)
      uc.call(student_name: "민준")
      expect(captured_actor).to eq("agent")
    end

    it "LLM 호출 실패 → 결정적 폴백 (graceful)" do
      failing_backend = Class.new(Sowing::Eval::Backends::Base) do
        def chat(system:, user:)
          raise "LLM down"
        end
      end
      uc = described_class.new(db: db, vault_dir: vault_dir,
        llm_backend: failing_backend.new, clock: clock)
      result = uc.call(student_name: "민준")
      expect(result).to be_success
      content = vault_dir.join(".sowing/synth/students/민준.md").read
      expect(content).to include("결정적 합성") # fallback marker
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, clock: clock)
    }

    it "entity 없으면 Failure(:entity_not_found)" do
      result = use_case.call(student_name: "없는학생")
      expect(result).to be_failure
      expect(result.failure).to eq(:entity_not_found)
    end

    it "mention 없으면 Failure(:no_mentions)" do
      seed_entity(name: "고립학생")
      result = use_case.call(student_name: "고립학생")
      expect(result.failure).to eq(:no_mentions)
    end

    it "mention 은 있는데 entries 가 사라진 경우 Failure(:no_entries)" do
      entity_id = seed_entity(name: "외톨이")
      seed_mention(entity_id: entity_id, entry_id: "01PHANTOM0000000000000001")
      result = use_case.call(student_name: "외톨이")
      expect(result.failure).to eq(:no_entries)
    end

    it "vault 의 마크다운 파일이 사라진 경우에도 인덱스만으로 처리 (graceful)" do
      seed_entry(id: "01EXT00000000000000000C1",
        body: "민준이 등장",
        created_at: "2026-05-01T10:00:00+09:00")
      entity_id = seed_entity(name: "민준")
      seed_mention(entity_id: entity_id, entry_id: "01EXT00000000000000000C1")

      # 마크다운 파일만 삭제 — 인덱스는 남음
      File.unlink(vault_dir.join("00_Inbox/01EXT00000000000000000C1.md"))

      result = use_case.call(student_name: "민준")
      expect(result).to be_success # 빈 excerpt 라도 디제스트 작성
    end

    it "멱등 — 같은 학생 재합성 시 atomic 덮어쓰기" do
      seed_entry(id: "01M0000000000000000000001",
        body: "민준이 메모", created_at: "2026-05-01T10:00:00+09:00")
      entity_id = seed_entity(name: "민준")
      seed_mention(entity_id: entity_id, entry_id: "01M0000000000000000000001")

      use_case.call(student_name: "민준")
      first_mtime = vault_dir.join(".sowing/synth/students/민준.md").mtime

      sleep 1.1 # mtime 1초 단위
      use_case.call(student_name: "민준")
      second_mtime = vault_dir.join(".sowing/synth/students/민준.md").mtime

      expect(second_mtime).to be > first_mtime
    end
  end

  describe "ROADMAP 검증 시나리오 — '민준' 디제스트" do
    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, clock: clock)
    }

    it "등장한 메모·기록 모두 인용 + 출처 링크 + 변화 요약 (결정적 모드는 timeline)" do
      seed_entry(id: "01M0000000000000000000001",
        body: "민준이는 발표 안 함",
        created_at: "2026-04-10T10:00:00+09:00")
      seed_entry(id: "01R0000000000000000000001",
        body: "민준이가 자원 발표",
        created_at: "2026-05-05T10:00:00+09:00", mode: "record",
        path: "30_Records/2026/학생기록/민준-변화.md")
      entity_id = seed_entity(name: "민준")
      seed_mention(entity_id: entity_id, entry_id: "01M0000000000000000000001")
      seed_mention(entity_id: entity_id, entry_id: "01R0000000000000000000001")

      use_case.call(student_name: "민준")
      content = vault_dir.join(".sowing/synth/students/민준.md").read

      # ROADMAP 검증 항목들
      expect(content).to include("[[00_Inbox/01M0000000000000000000001.md]]")  # 메모 출처
      expect(content).to include("[[30_Records/2026/학생기록/민준-변화.md]]")  # 기록 출처
      expect(content).to include("발표 안 함")
      expect(content).to include("자원 발표")
      expect(content).to include("시간순") # 변화 요약 (결정적 모드 representation)
    end
  end
end
