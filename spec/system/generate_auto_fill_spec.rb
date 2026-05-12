# frozen_string_literal: true

require "rack/test"
require "fileutils"

# Phase 16 P16-T05 — 생기부 자동 채우기 (학생 이름 → 1년치 entries 자동 수집).
RSpec.describe "Generate Auto-Fill (Phase 16 P16-T05)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete

    vault = Sowing::Core::Paths.vault_dir
    FileUtils.rm_rf(vault.join("00_Inbox"))
    FileUtils.rm_rf(vault.join("20_Notes"))
    FileUtils.rm_rf(vault.join("30_Records"))
  end

  # ── 시드 helper ─────────────────────────────────────────────
  def seed_record(title:, body:, category: "학생기록", created_at: Time.new(2026, 5, 12, 9))
    Sowing::Capture.reset_repo!
    use_case = Sowing::UseCases::CreateRecord.new(
      vault_repo: Sowing::Repositories::VaultRepo.new(vault_dir: Sowing::Core::Paths.vault_dir),
      index_repo: Sowing::Repositories::IndexRepo.new,
      clock: double("clock", now: created_at)
    )
    result = use_case.call(title: title, body: body, category: category, tags: [])
    raise "시드 실패: #{result.failure}" unless result.success?
    result.value!
  end

  describe "GET /generate/student_record?student=NAME" do
    context "학생 이름에 매칭되는 entry 가 있을 때" do
      before do
        seed_record(
          title: "5월 첫 주",
          body: "김철수가 1단원 수업에 적극 발표함. 모둠 활동 리더십 보임.",
          created_at: Time.new(2026, 5, 5, 9)
        )
        seed_record(
          title: "5월 둘째 주",
          body: "김철수와 친구들 갈등 — 김철수가 사과로 해결, 교우 관계 회복.",
          created_at: Time.new(2026, 5, 12, 9)
        )
        seed_record(
          title: "6월 평가",
          body: "김철수 수행평가 95점, 단원 시험 우수.",
          created_at: Time.new(2026, 6, 3, 9)
        )
        # 학생 이름 미포함 — 카운트 0 검증용
        seed_record(title: "다른 학생", body: "이영희는 미술 시간 활약.")
      end

      it "200 + 자동 수집 결과 표시" do
        get "/generate/student_record", student: "김철수"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include("김철수")
        expect(last_response.body).to include("✅")
        expect(last_response.body).to include("발견")
      end

      it "학습 활동 textarea 에 수업·발표·평가 entry 들어감" do
        get "/generate/student_record", student: "김철수"
        # learning_activities textarea 내부에 keyword 매칭 entry 가 포함
        expect(last_response.body).to include("(5월) 김철수가 1단원 수업에 적극 발표함")
        expect(last_response.body).to include("(6월) 김철수 수행평가 95점")
      end

      it "행동 특성 textarea 에 교우·갈등 entry 들어감" do
        get "/generate/student_record", student: "김철수"
        expect(last_response.body).to include("(5월) 김철수와 친구들 갈등")
      end

      it "이름 미포함 entry 는 자동 채움에서 제외" do
        get "/generate/student_record", student: "김철수"
        # "이영희" entry 의 본문은 김철수 form 에 없어야 함
        body = last_response.body
        expect(body).not_to include("이영희는 미술 시간 활약")
      end

      it "학생 이름이 textarea form 값 student_name 에도 자동 채워짐" do
        get "/generate/student_record", student: "김철수"
        expect(last_response.body).to include('name="student_name" required')
        expect(last_response.body).to include('value="김철수"')
      end
    end

    context "이름에 매칭되는 entry 가 없을 때" do
      it "친절한 빈 결과 안내 표시" do
        get "/generate/student_record", student: "없는학생"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include("ℹ️")
        expect(last_response.body).to include("entry 가 없습니다")
      end
    end

    context "?student= 없이 (auto 모드 비활성)" do
      it "기본 빈 form (auto 안내 미표시)" do
        get "/generate/student_record"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include("자동 채우기")
        expect(last_response.body).not_to include("✅")
        expect(last_response.body).not_to include("ℹ️")
      end
    end
  end

  describe "auto 모드 후 form 제출 — round-trip" do
    before do
      seed_record(title: "기록", body: "김철수는 발표 우수.",
        created_at: Time.new(2026, 5, 5, 9))
    end

    it "자동 채워진 form 을 그대로 POST 하면 다운로드 작동" do
      get "/generate/student_record", student: "김철수"

      # form 의 hidden·visible 값을 추출하여 POST — 통합 동작 검증
      post "/generate/student_record", {
        student_name: "김철수",
        grade: "3",
        date: "2026-05-12",
        teacher_name: "이선생",
        learning_activities: "- (5월) 김철수는 발표 우수.",
        behavioral_observations: "",
        format: "markdown"
      }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("**대상**: 김철수")
      expect(last_response.body).to include("김철수는 발표 우수")
    end
  end

  describe "Archive 자동 제외 (ADR-017)" do
    it "보관된 record 는 자동 채움에서 제외" do
      record = seed_record(
        title: "졸업 전 기록",
        body: "김철수 학생 졸업 직전 활동.",
        created_at: Time.new(2025, 12, 1, 9)
      )
      # 보관 처리
      Sowing::Knowledge.archive(record.id, reason: "졸업")

      get "/generate/student_record", student: "김철수"
      # 보관된 entry 는 학습/행동 textarea 에 들어가면 안 됨
      expect(last_response.body).not_to include("김철수 학생 졸업 직전 활동")
    end
  end
end
