# frozen_string_literal: true

require "front_matter_parser"
require "json"

RSpec.describe Sowing::UseCases::ExtractEntities do
  let(:db) { Sowing::Core::DB.connection }

  before do
    db[:entity_mentions].delete
    db[:entities].delete
  end

  describe "#call (결정적 fallback — backend 없음)" do
    subject(:use_case) { described_class.new(db: db) }

    it "ent-001 시드 — 단일 학생 + 단일 과목" do
      body = "오늘 5학년 3반 민준이가 수학 시간에 처음으로 발표를 자원했다."
      result = use_case.call(entry_id: "01TEST00000000000000000001", body: body)

      expect(result).to be_success
      entities = result.value!
      expect(entities["students"]).to include("민준")
      expect(entities["subjects"]).to include("수학")
    end

    it "ent-002 시드 — 다중 학생 + 다중 과목 + 위치" do
      body = "도덕 시간에 도서관으로 옮겨 갈등 해결 활동을 진행했다. 민준이와 서연이가 한 모둠, 지호는 다른 모둠에 들어갔다. 국어 시간 글쓰기 활동에서도 같은 모둠 구성을 시도해 볼 만하다."
      result = use_case.call(entry_id: "01TEST00000000000000000002", body: body)

      entities = result.value!
      expect(entities["students"]).to contain_exactly("민준", "서연", "지호")
      expect(entities["subjects"]).to contain_exactly("도덕", "국어")
      expect(entities["locations"]).to contain_exactly("도서관")
    end

    it "ent-003 시드 — entity 없음 (false positive 0)" do
      body = "오늘 출근길에 학기 운영 방식을 곰곰이 생각해 봤다. 매주 수업 회고를 짧게 남기는 습관을 만들면 다음 학기 준비가 훨씬 수월할 것 같다."
      result = use_case.call(entry_id: "01TEST00000000000000000003", body: body)

      entities = result.value!
      expect(entities["students"]).to eq([]) # 학생 인명 없음
      expect(entities["locations"]).to eq([]) # 위치 없음
      # subjects 는 "수업" 이 일반어라 추출되지 않음 (subjects 사전에 없음)
    end

    it "흔한 명사는 학생 이름으로 오인 안 함 (EXCLUDE_NAMES)" do
      body = "오늘이 마지막 수업이다. 학생들이 발표했다."
      result = use_case.call(entry_id: "01TEST00000000000000000004", body: body)
      expect(result.value!["students"]).to eq([])
    end
  end

  describe "DB 저장 (entities + entity_mentions)" do
    subject(:use_case) { described_class.new(db: db) }

    it "신규 entity 는 mention_count=1 + first/last_seen_at" do
      body = "민준이가 수학 시간 잘 했다."
      use_case.call(entry_id: "01ENTRY0000000000000000001", body: body)

      memo = db[:entities].where(name: "민준").first
      expect(memo[:type]).to eq("student")
      expect(memo[:mention_count]).to eq(1)
      expect(memo[:first_seen_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "같은 entity 가 다른 entry 에서 또 등장 → mention_count 증가" do
      body1 = "민준이가 발표 자원했다."
      body2 = "민준이는 수학 잘 한다."
      use_case.call(entry_id: "01ENTRY0000000000000000001", body: body1)
      use_case.call(entry_id: "01ENTRY0000000000000000002", body: body2)

      memo = db[:entities].where(name: "민준").first
      expect(memo[:mention_count]).to eq(2)
      expect(db[:entity_mentions].where(entity_id: memo[:id]).count).to eq(2)
    end

    it "같은 entry 에서 두 번 호출해도 mention 중복 추가 안 함 (멱등)" do
      body = "민준이가 발표 자원했다."
      use_case.call(entry_id: "01ENTRY0000000000000000001", body: body)
      use_case.call(entry_id: "01ENTRY0000000000000000001", body: body)

      mentions = db[:entity_mentions].where(entry_id: "01ENTRY0000000000000000001").count
      expect(mentions).to eq(1) # 같은 entry 같은 entity 는 한 번만
    end

    it "type 별 분리 — 같은 이름이 student 와 subject 로 충돌 없음" do
      # "도덕" 은 subject 사전에 있음. 만약 학생 이름이 "도덕" 이라면 → 다른 type 으로 저장 가능 (UNIQUE(type, name))
      body = "도덕 시간이 좋았다."
      use_case.call(entry_id: "01ENTRY0000000000000000001", body: body)
      expect(db[:entities].where(name: "도덕", type: "subject").count).to eq(1)
    end
  end

  describe "LLM backend 모드 (옵트인)" do
    let(:llm_response) {
      JSON.generate({
        "students" => ["민준", "서연"],
        "subjects" => ["수학"],
        "locations" => ["교실"]
      })
    }
    let(:fake_backend) {
      Sowing::Eval::Backends::FakeBackend.new(responses: [llm_response])
    }
    subject(:use_case) { described_class.new(db: db, llm_backend: fake_backend) }

    it "LLM 응답 → 그대로 사용" do
      result = use_case.call(entry_id: "01TEST00000000000000000001", body: "임의 본문")
      expect(result.value!["students"]).to contain_exactly("민준", "서연")
      expect(result.value!["subjects"]).to eq(["수학"])
    end

    it "LLM 응답에 시스템 prompt 포함 (한국어 안내)" do
      use_case.call(entry_id: "01TEST00000000000000000001", body: "본문")
      captured = fake_backend.captured_prompts.first
      expect(captured[:system]).to include("학생 이름")
      expect(captured[:system]).to include("JSON")
      expect(captured[:user]).to include("본문")
    end

    it "LLM JSON 파싱 실패 → 결정적 fallback" do
      bad_backend = Sowing::Eval::Backends::FakeBackend.new(responses: ["not json"])
      uc = described_class.new(db: db, llm_backend: bad_backend)
      result = uc.call(entry_id: "01TEST00000000000000000001", body: "민준이가 발표했다.")
      # fallback 으로 결정적 추출 동작
      expect(result.value!["students"]).to include("민준")
    end

    it "audit log actor=agent 로 기록 (Phase 9 with_actor 통합)" do
      audit = Sowing::Core::AuditLog.new(
        vault_dir: Pathname.new(Dir.mktmpdir("extract-audit-spec-"))
      )
      Sowing::Core::AuditLog.instance = audit
      begin
        # ExtractEntities 는 audit 호출 안 하지만 with_actor 블록에서 실행됨
        # 향후 audit_mutation! 호출이 추가되면 actor=agent 기록될 것을 보장.
        # 본 spec 은 with_actor 통합 사용 검증.
        captured_actor = nil
        # Backends 호출 시점에 current_actor 확인 — fake_backend 는 사용 안 하고
        # intercepted_backend 만 사용 (실제 actor 캡처 위해).
        intercepted_backend = Class.new(Sowing::Eval::Backends::Base) do
          define_method(:chat) do |system:, user:|
            captured_actor = Sowing::Core::AuditLog.current_actor
            JSON.generate({"students" => [], "subjects" => [], "locations" => []})
          end
        end
        intercepted_uc = described_class.new(db: db, llm_backend: intercepted_backend.new)
        intercepted_uc.call(entry_id: "01X", body: "본문")
        expect(captured_actor).to eq("agent")
      ensure
        Sowing::Core::AuditLog.instance = nil
      end
    end
  end

  describe "Eval 통합 — entity_extraction task corpus 회귀" do
    it "ent-001~003 모두 결정적 추출로 처리 (graceful)" do
      hand_dir = File.expand_path("../../eval/corpus/teacher_writings/hand_crafted", __dir__)
      ent_files = Dir.glob(File.join(hand_dir, "ent-*.md"))
      expect(ent_files.size).to be >= 3

      ent_files.each do |path|
        body = FrontMatterParser::Parser.new(:md).call(File.read(path)).content
        result = described_class.new(db: db).call(
          entry_id: "01TEST#{File.basename(path, ".md")}",
          body: body
        )
        expect(result).to be_success
      end
    end
  end
end
