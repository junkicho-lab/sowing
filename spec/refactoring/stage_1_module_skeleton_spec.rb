# frozen_string_literal: true

# Phase R Stage 1 — 4 Bounded Context 모듈 골격 + Façade 검증.
# 실제 구현은 Stage 2~4 에서. 본 spec 은 인터페이스 존재 + arch-check pass.
RSpec.describe "Phase R Stage 1 — Bounded Context 골격" do
  describe "4 모듈 namespace 존재" do
    it "Sowing::Capture 정의됨" do
      expect(defined?(Sowing::Capture)).to eq("constant")
    end

    it "Sowing::Knowledge 정의됨" do
      expect(defined?(Sowing::Knowledge)).to eq("constant")
    end

    it "Sowing::Insight 정의됨" do
      expect(defined?(Sowing::Insight)).to eq("constant")
    end

    it "Sowing::Output 정의됨" do
      expect(defined?(Sowing::Output)).to eq("constant")
    end

    it "Sowing::Core 정의됨 (R1-T01 rename 결과)" do
      expect(defined?(Sowing::Core)).to eq("constant")
    end
  end

  describe "Capture::public_api" do
    # Stage 2 R2-T03 — Capture Façade 실 구현. NotImplementedError stub 폐기.
    # 본 spec 은 Façade 가 "응답 가능" 만 검증 (단위 spec 은 spec/capture/ 참조).
    it ".create_item / .find / .recent 모두 호출 가능 (Stage 2 R2 완료)" do
      expect(Sowing::Capture).to respond_to(:create_item)
      expect(Sowing::Capture).to respond_to(:find)
      expect(Sowing::Capture).to respond_to(:recent)
    end

    it ".create_item 은 body 가 비어있으면 ArgumentError" do
      expect { Sowing::Capture.create_item(body: "") }
        .to raise_error(ArgumentError, /body/)
    end
  end

  describe "Knowledge::public_api" do
    # Stage 3 R3-T03~T04 — create_record / create_plan 실 구현. stub 폐기.
    # archive / unarchive 만 R3-T05 까지 NotImplementedError stub 유지.
    it ".create_record / .create_plan 호출 가능 (Stage 3 R3-T04 완료)" do
      expect(Sowing::Knowledge).to respond_to(:create_record)
      expect(Sowing::Knowledge).to respond_to(:create_plan)
    end

    it ".archive / .unarchive 만 stub 유지 (R3-T05 에서 실 구현)" do
      expect { Sowing::Knowledge.archive("id", reason: "졸업") }
        .to raise_error(NotImplementedError, /ADR-017/)
      expect { Sowing::Knowledge.unarchive("id") }
        .to raise_error(NotImplementedError, /Stage 3 R3-T05/)
    end
  end

  describe "Insight::public_api" do
    it "SYNTHESIZER_TYPES 18 개 (17 합성기 + self-mirror)" do
      expect(Sowing::Insight::SYNTHESIZER_TYPES.size).to eq(18)
      expect(Sowing::Insight::SYNTHESIZER_TYPES).to include("self-mirror")
    end

    it ".generate / .pending_count / .accept / .reject stub" do
      expect { Sowing::Insight.generate(type: "students") }.to raise_error(NotImplementedError)
      expect { Sowing::Insight.pending_count }.to raise_error(NotImplementedError)
    end
  end

  describe "Output::public_api" do
    it "TEMPLATE_TYPES 5 종 (ADR-018, 게이트 #3 c)" do
      expect(Sowing::Output::TEMPLATE_TYPES).to eq(
        %i[student_record consultation meeting_minutes project_proposal budget_request]
      )
    end

    it "FORMATS 3 종 (markdown·pdf·docx)" do
      expect(Sowing::Output::FORMATS).to eq(%i[markdown pdf docx])
    end

    it ".generate stub" do
      expect { Sowing::Output.generate(type: :student_record) }
        .to raise_error(NotImplementedError, /Stage 4b/)
    end
  end

  describe "bin/sowing-arch-check — 의존성 룰" do
    it "현재 코드 0 위반 (Stage 1 끝, 옛 코드는 core/ 만 참조)" do
      out = `bin/sowing-arch-check --strict 2>&1`
      expect($?.exitstatus).to eq(0), "arch-check 위반:\n#{out}"
      expect(out).to include("✅ arch-check: 모듈 의존성 룰 0 위반")
    end

    it "ALLOWED_DEPS 정의 (Capture < Knowledge < Insight < Output)" do
      out = `bin/sowing-arch-check 2>&1`
      expect(out).to include("capture      → core")
      expect(out).to include("knowledge    → core, capture")
      expect(out).to include("output       → core, capture, knowledge, insight")
    end
  end
end
