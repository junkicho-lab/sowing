# frozen_string_literal: true

# Phase R R4b-followup — FontConfig (한글 PDF 폰트 resolver).
RSpec.describe Sowing::Output::FontConfig do
  describe ".resolve" do
    it "vendor/fonts/Pretendard-Regular.ttf 또는 system fallback 발견" do
      # 본 spec 환경은 vendored Pretendard 보유 가정
      path = described_class.resolve
      expect(File.file?(path)).to be(true)
      expect(File.extname(path)).to match(/\A\.(ttf|otf)\z/i)
    end
  end

  describe ".available?" do
    it "vendored 폰트가 있으면 true" do
      expect(described_class.available?).to be(true)
    end

    it "raise 없이 false 반환 (폰트 누락 시)" do
      stubbed = []
      allow(described_class).to receive(:build_candidates).and_return(stubbed)
      expect(described_class.available?).to be(false)
    end
  end

  describe "ENV 우선" do
    it "SOWING_PDF_FONT 가 설정되어 있으면 그 경로를 첫 후보로" do
      vendored = described_class::VENDORED_REGULAR
      ENV["SOWING_PDF_FONT"] = vendored
      expect(described_class.resolve).to eq(vendored)
    ensure
      ENV.delete("SOWING_PDF_FONT")
    end
  end

  describe ".bold_path" do
    it "vendored Bold 가 있으면 경로 반환" do
      expect(described_class.bold_path).to end_with("Pretendard-Bold.ttf")
    end
  end

  describe "FontNotFound 메시지" do
    it "어느 후보도 없으면 설치 가이드 포함 raise" do
      allow(described_class).to receive(:build_candidates).and_return([])
      expect { described_class.resolve }.to raise_error(
        described_class::FontNotFound, /Pretendard|SOWING_PDF_FONT/
      )
    end
  end
end
