# frozen_string_literal: true

# Phase R R4b-followup — PdfRenderer (markdown → PDF binary).
RSpec.describe Sowing::Output::PdfRenderer do
  before(:all) do
    unless Sowing::Output::FontConfig.available?
      skip "한글 폰트 없음 — vendor/fonts/Pretendard-Regular.ttf 또는 SOWING_PDF_FONT 설정 필요"
    end
  end

  let(:renderer) { described_class.new }

  describe "#render — basic" do
    it "단순 마크다운을 PDF binary 로 변환" do
      bytes = renderer.render("# 제목\n\n본문 내용.")
      expect(bytes).to be_a(String)
      expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
      expect(bytes[0, 4]).to eq("%PDF")
    end

    it "PDF 버전 1.x 헤더" do
      bytes = renderer.render("# x")
      expect(bytes[0, 8]).to match(/\A%PDF-1\.\d/)
    end

    it "한글 텍스트도 동일 흐름 (글리프 누락 raise 없음)" do
      bytes = renderer.render("# 학생부\n\n김철수 학생은 우수합니다.")
      expect(bytes.bytesize).to be > 1000
    end
  end

  describe "마크다운 features 지원" do
    it "H1·H2·H3 모두 렌더 가능" do
      md = "# H1\n\n## H2\n\n### H3\n\n본문"
      bytes = renderer.render(md)
      expect(bytes.bytesize).to be > 1000
    end

    it "bold·italic 인라인" do
      md = "**굵게** 와 *기울임* 혼합 문장."
      bytes = renderer.render(md)
      expect(bytes.bytesize).to be > 1000
    end

    it "unordered list" do
      md = "- 항목 1\n- 항목 2\n- 항목 3\n"
      bytes = renderer.render(md)
      expect(bytes.bytesize).to be > 1000
    end

    it "markdown table (prawn-table 통합)" do
      md = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n"
      bytes = renderer.render(md)
      expect(bytes.bytesize).to be > 1000
    end

    it "thematic break (---)" do
      bytes = renderer.render("위\n\n---\n\n아래")
      expect(bytes.bytesize).to be > 1000
    end
  end

  describe "사용자 지정 폰트" do
    it "font_path 옵션으로 다른 TTF 사용" do
      custom = Sowing::Output::FontConfig::VENDORED_REGULAR
      r = described_class.new(font_path: custom)
      bytes = r.render("# 테스트")
      expect(bytes[0, 4]).to eq("%PDF")
    end
  end

  describe "5 default templates 통합 (R4b-followup 검증 본진)" do
    Sowing::Output::TEMPLATE_TYPES.each do |type|
      it "type: #{type.inspect} — Façade 경유 PDF 렌더 성공" do
        bytes = Sowing::Output.generate(
          type: type, format: :pdf,
          # 빈 locals 으로도 ERB 의 || 폴백으로 렌더 가능
        )
        expect(bytes[0, 4]).to eq("%PDF")
        expect(bytes.bytesize).to be > 1000
      end
    end
  end
end
