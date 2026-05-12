# frozen_string_literal: true

require "rack/test"
require "fileutils"

# Phase 16 P16-T06 — Insight 학생 디제스트 직접 연계.
RSpec.describe "Generate × Insight Digest Integration (Phase 16 P16-T06)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entries].delete
    FileUtils.rm_rf(vault_dir.join(".sowing/synth"))
    Sowing::Insight.reset_repo!
  end

  after { Sowing::Insight.reset_repo! }

  # 학생 디제스트 합성 결과를 직접 작성하여 시뮬레이션.
  # (실제 합성기 호출은 LLM·entries 의존이 커서 spec 에서 우회.)
  def seed_student_digest(student_name, body: "정형 학생 관찰 합성 본문.")
    repo = Sowing::Insight::SynthesisRepo.new(vault_dir: vault_dir)
    synth = Sowing::Insight::Synthesis.new(
      type: :students,
      target: "student:#{student_name}",
      title: "학생 관찰: #{student_name}",
      body: body,
      synth_at: Time.new(2026, 5, 12, 9, 0, 0),
      source_count: 12
    )
    Sowing::Insight.repo = repo
    repo.write(synth, slug: student_name)
    synth
  end

  describe "GET /generate/student_record?student=NAME 합성 결과 존재" do
    before do
      seed_student_digest("김철수", body: "## 학습 활동\n적극 발표.\n\n## 행동\n친구와 협력.")
    end

    it "기본 (raw entries 모드) — 합성 디제스트 안내 노출" do
      get "/generate/student_record", student: "김철수"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("합성된 디제스트")
      expect(last_response.body).to include("✨ 디제스트로 채우기")
    end

    it "use_synth=1 — 합성 본문이 learning_activities 에 채워짐" do
      get "/generate/student_record", student: "김철수", use_synth: "1"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("학생 디제스트 (Insight 합성)")
      # textarea 안에 합성 본문이 들어감
      expect(last_response.body).to include("적극 발표")
      expect(last_response.body).to include("친구와 협력")
    end

    it "use_synth=1 후 — '원본 entries 로 다시' toggle 노출" do
      get "/generate/student_record", student: "김철수", use_synth: "1"
      expect(last_response.body).to include("원본 entries 로 다시 채우기")
    end

    it "Insight 합성 결과 메타 (synth_at·source_count) 노출" do
      get "/generate/student_record", student: "김철수", use_synth: "1"
      expect(last_response.body).to include("2026-05-12 합성")
      expect(last_response.body).to include("원본 12건 기반")
    end
  end

  describe "합성 결과 없음 — toggle 미노출 (자연스러운 graceful)" do
    it "이름은 있어도 디제스트 없으면 기본 자동 채움만 작동" do
      get "/generate/student_record", student: "없는학생"
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include("합성된 디제스트")
      expect(last_response.body).not_to include("디제스트로 채우기")
    end
  end

  describe "round-trip: 디제스트 모드 → POST 다운로드" do
    before do
      seed_student_digest("이영희", body: "구체적 디제스트 본문.")
    end

    it "use_synth 로 채워진 learning_activities 가 마크다운 출력에 반영" do
      get "/generate/student_record", student: "이영희", use_synth: "1"

      # 사용자가 form 그대로 제출 (실제 브라우저 동작 시뮬레이션 — 본문 추출은 단순화)
      post "/generate/student_record", {
        student_name: "이영희",
        grade: "3",
        date: "2026-05-12",
        teacher_name: "이선생",
        learning_activities: "구체적 디제스트 본문.",
        behavioral_observations: "",
        format: "markdown"
      }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("**대상**: 이영희")
      expect(last_response.body).to include("구체적 디제스트 본문")
    end
  end

  describe "Insight.find 안전성 — 합성기 폴더 부재 graceful" do
    before do
      FileUtils.rm_rf(vault_dir.join(".sowing/synth"))
      Sowing::Insight.reset_repo!
    end

    it "synth 폴더가 없어도 raise 없이 진행" do
      get "/generate/student_record", student: "김영수"
      expect(last_response.status).to eq(200)
    end
  end
end
