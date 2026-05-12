# frozen_string_literal: true

require "rack/test"

# Phase 16 P16-T04 — 공식 양식 생성 페이지 (5 templates × 3 formats).
RSpec.describe "Generate UI (Phase 16 P16-T04)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before { header "Host", "127.0.0.1" }

  describe "GET /generate (landing)" do
    before { get "/generate" }

    it "200 + 5 template 카드 노출" do
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("공식 양식 생성")
      expect(last_response.body).to include("생기부")
      expect(last_response.body).to include("상담부")
      expect(last_response.body).to include("회의록")
      expect(last_response.body).to include("사업계획서")
      expect(last_response.body).to include("예산요구서")
    end

    it "각 카드가 /generate/:template 으로 링크" do
      Sowing::Output::TEMPLATE_TYPES.each do |type|
        expect(last_response.body).to include("/generate/#{type}")
      end
    end
  end

  describe "GET /generate/:template — form 표시" do
    Sowing::Output::TEMPLATE_TYPES.each do |type|
      it "type: #{type.inspect} — form 200" do
        get "/generate/#{type}"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include("<form")
        expect(last_response.body).to include("action=\"/generate/#{type}\"")
        expect(last_response.body).to include('name="format"') # 형식 선택 radio
      end
    end

    it "지원하지 않는 template — 404" do
      get "/generate/unknown_type"
      expect(last_response.status).to eq(404)
    end
  end

  describe "POST /generate/student_record — 생기부 다운로드" do
    let(:base_params) {
      {
        student_name: "김철수",
        grade: "3", grade_class: "5",
        date: "2026-05-12", teacher_name: "이선생",
        academic_year: "2026",
        learning_activities: "수업 적극 참여, 발표 우수.",
        behavioral_observations: "친구들과 잘 어울리며 모둠 활동 리더십."
      }
    }

    it "format=markdown — 마크다운 다운로드 (200, text/markdown)" do
      post "/generate/student_record", base_params.merge(format: "markdown")
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("text/markdown")
      expect(last_response.body).to include("**대상**: 김철수")
      expect(last_response.body).to include("수업 적극 참여")
    end

    it "format=pdf — PDF binary" do
      post "/generate/student_record", base_params.merge(format: "pdf")
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to eq("application/pdf")
      expect(last_response.body[0, 4]).to eq("%PDF")
    end

    it "format=docx — DOCX binary" do
      post "/generate/student_record", base_params.merge(format: "docx")
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("wordprocessingml")
      expect(last_response.body[0, 2].bytes).to eq([0x50, 0x4B])
    end

    it "한글 파일명 — Content-Disposition RFC 5987" do
      post "/generate/student_record", base_params.merge(format: "pdf")
      disp = last_response.headers["Content-Disposition"]
      expect(disp).to include("attachment")
      expect(disp).to include("filename*=UTF-8''")
      expect(disp).to include(".pdf")
    end
  end

  describe "POST /generate/consultation — 상담부" do
    it "필수 항목 입력 후 마크다운 생성" do
      post "/generate/consultation", {
        consultation_date: "2026-05-12",
        consultee: "김철수 학부모",
        consultation_method: "대면",
        teacher_name: "이선생",
        consultation_content: "진로 상담 — 이공계 진학 희망",
        follow_up: "다음 학기 모의고사 점수 점검",
        format: "markdown"
      }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("**상담 대상**: 김철수 학부모")
      expect(last_response.body).to include("진로 상담")
    end
  end

  describe "POST /generate/meeting_minutes — 회의록" do
    it "안건 multi-line 파싱" do
      post "/generate/meeting_minutes", {
        meeting_title: "3학년 교과협의회",
        meeting_date: "2026-05-12",
        meeting_time: "14:00",
        location: "교사회의실",
        attendees: "김교사, 이교사, 박교사",
        recorder: "이선생",
        agenda: "1단원 평가\n체험학습 일정\n예산 확정",
        discussion: "각 안건 활발히 논의됨.",
        decisions: "1단원 평가는 수행평가 60%\n체험학습 5월 둘째 주",
        next_meeting: "5월 20일 14시",
        format: "markdown"
      }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("1단원 평가")
      expect(last_response.body).to include("3학년 교과협의회")
      expect(last_response.body).to include("김교사, 이교사, 박교사")
    end
  end

  describe "POST /generate/budget_request — 예산요구서" do
    it "line_items 동적 입력 → 표 렌더" do
      post "/generate/budget_request", {
        request_title: "도서 구입",
        request_date: "2026-05-12",
        requester: "이선생",
        department: "국어과",
        fiscal_year: "2026",
        total_amount: "150000",
        rationale: "1학기 독서 인증제용",
        line_items: {
          "0" => {"name" => "교과서", "unit_price" => "15000", "quantity" => "10", "amount" => "150000", "note" => ""}
        },
        execution_plan: "5월 발주, 6월 입고.",
        format: "markdown"
      }
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("**총 요구액**: 150000원")
      expect(last_response.body).to include("교과서")
    end
  end

  describe "format 검증" do
    it "지원하지 않는 format → markdown default" do
      post "/generate/student_record", {student_name: "x", format: "invalid"}
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("text/markdown")
    end
  end
end
