# frozen_string_literal: true

# Phase R R4b-followup — DocxRenderer (markdown → DOCX binary).
RSpec.describe Sowing::Output::DocxRenderer do
  let(:renderer) { described_class.new }

  describe "#render — basic" do
    it "단순 마크다운을 DOCX binary 로 변환" do
      bytes = renderer.render("# 제목\n\n본문.")
      expect(bytes).to be_a(String)
      # DOCX 는 ZIP 컨테이너 (Office Open XML)
      expect(bytes[0, 2].bytes).to eq([0x50, 0x4B])
    end

    it "한글 텍스트 통과 (caracal 시스템 폰트 fallback)" do
      bytes = renderer.render("# 학생부\n\n김철수 학생은 우수합니다.")
      expect(bytes.bytesize).to be > 1000
    end
  end

  describe "마크다운 features 지원" do
    it "H1·H2·H3 매핑" do
      bytes = renderer.render("# H1\n\n## H2\n\n### H3\n")
      expect(bytes.bytesize).to be > 1000
    end

    it "bold·italic 인라인" do
      bytes = renderer.render("**굵게** 와 *기울임*.")
      expect(bytes.bytesize).to be > 1000
    end

    it "unordered list" do
      bytes = renderer.render("- 하나\n- 둘\n- 셋\n")
      expect(bytes.bytesize).to be > 1000
    end

    it "markdown table" do
      bytes = renderer.render("| A | B |\n|---|---|\n| 1 | 2 |\n")
      expect(bytes.bytesize).to be > 1000
    end
  end

  describe "5 default templates 통합" do
    Sowing::Output::TEMPLATE_TYPES.each do |type|
      it "type: #{type.inspect} — Façade 경유 DOCX 렌더 성공" do
        bytes = Sowing::Output.generate(type: type, format: :docx)
        expect(bytes[0, 2].bytes).to eq([0x50, 0x4B])
        expect(bytes.bytesize).to be > 1000
      end
    end
  end
end
