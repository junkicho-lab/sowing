# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Phase R Stage 4b — Sowing::Output Façade.
RSpec.describe "Sowing::Output Façade (Stage 4b)" do
  after { Sowing::Output.reset_registry! }

  describe ".generate (markdown — MVP)" do
    Sowing::Output::TEMPLATE_TYPES.each do |type|
      it "type: #{type.inspect} — 빈 locals 으로도 렌더링 성공 (default ERB)" do
        result = Sowing::Output.generate(type: type)
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end
    end

    it "student_record — locals 적용" do
      result = Sowing::Output.generate(
        type: :student_record,
        student_name: "김철수",
        grade: 3,
        date: "2026-05-12",
        teacher_name: "이선생",
        learning_activities: "수업 참여 적극적",
        behavioral_observations: "친구들과 잘 어울림"
      )
      expect(result).to include("**대상**: 김철수")
      expect(result).to include("**학년/반**: 3")
      expect(result).to include("**작성일**: 2026-05-12")
      expect(result).to include("수업 참여 적극적")
    end

    it "consultation — 한 줄 옵션 처리" do
      result = Sowing::Output.generate(
        type: :consultation,
        consultation_date: "2026-05-12",
        consultee: "학부모",
        teacher_name: "이선생",
        consultation_content: "1학기 성적 상담"
      )
      expect(result).to include("**상담 일시**: 2026-05-12")
      expect(result).to include("**상담 대상**: 학부모")
      expect(result).to include("1학기 성적 상담")
    end

    it "meeting_minutes — agenda 배열 렌더" do
      result = Sowing::Output.generate(
        type: :meeting_minutes,
        meeting_title: "교과협의회",
        meeting_date: "2026-05-12",
        meeting_time: "14:00",
        attendees: ["김교사", "이교사", "박교사"],
        agenda: ["1단원 평가", "체험학습 일정", "예산 확정"]
      )
      expect(result).to include("**참석**: 김교사, 이교사, 박교사")
      expect(result).to include("1. 1단원 평가")
      expect(result).to include("3. 예산 확정")
    end

    it "budget_request — line_items 테이블 렌더" do
      result = Sowing::Output.generate(
        type: :budget_request,
        request_title: "도서구입",
        request_date: "2026-05-12",
        requester: "이선생",
        department: "국어과",
        fiscal_year: "2026",
        total_amount: "150000",
        line_items: [
          {name: "교과서", unit_price: "15000", quantity: "10", amount: "150000", note: ""}
        ]
      )
      expect(result).to include("| 교과서 | 15000 | 10 | 150000 |  |")
      expect(result).to include("**합계** | | | **150000** |")
    end

    it "write_to 지정 시 파일에 저장 + Pathname 반환" do
      Dir.mktmpdir do |dir|
        out_path = File.join(dir, "test.md")
        result = Sowing::Output.generate(
          type: :student_record, write_to: out_path,
          student_name: "테스트", date: "2026-05-12", teacher_name: "T"
        )
        expect(result).to be_a(Pathname)
        expect(result.read).to include("**대상**: 테스트")
      end
    end
  end

  describe ".generate — PDF / DOCX (R4b-followup 완료)" do
    # 본격적인 binary 출력 spec 은 spec/output/pdf_renderer_spec.rb /
    # docx_renderer_spec.rb 참조. 여기서는 Façade 가 dispatch 만 검증.
    it ":pdf — PDF binary 반환 (magic %PDF)" do
      bytes = Sowing::Output.generate(type: :student_record, format: :pdf,
        student_name: "T", grade: 1, date: "2026-05-12", teacher_name: "T")
      expect(bytes[0, 4]).to eq("%PDF")
    end

    it ":docx — ZIP binary 반환 (DOCX = ZIP container)" do
      bytes = Sowing::Output.generate(type: :student_record, format: :docx,
        student_name: "T", grade: 1, date: "2026-05-12", teacher_name: "T")
      expect(bytes[0, 2].bytes).to eq([0x50, 0x4B])
    end
  end

  describe ".generate — 검증" do
    it "type 5 종 외 → ArgumentError" do
      expect { Sowing::Output.generate(type: :unknown) }
        .to raise_error(ArgumentError, /type/)
    end

    it "format 3 종 외 → ArgumentError" do
      expect { Sowing::Output.generate(type: :student_record, format: :xml) }
        .to raise_error(ArgumentError, /format/)
    end
  end
end
