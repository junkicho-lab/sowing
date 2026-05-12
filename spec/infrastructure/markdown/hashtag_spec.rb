# frozen_string_literal: true

RSpec.describe Sowing::Core::Markdown::Hashtag do
  describe ".extract" do
    context "표준 인식" do
      it "한국어 태그를 추출한다" do
        expect(described_class.extract("오늘은 #수업 이 활기")).to eq(["수업"])
      end

      it "영문 태그를 추출한다" do
        expect(described_class.extract("주제 #english")).to eq(["english"])
      end

      it "숫자가 섞인 태그도 추출 (#1학년 OK)" do
        expect(described_class.extract("#1학년 학급")).to eq(["1학년"])
      end

      it "여러 태그 등장 순서대로, 중복은 제거" do
        expect(described_class.extract("#A 와 #B 그리고 #A")).to eq(%w[A B])
      end

      it "슬래시 계층 태그도 통째로 추출" do
        expect(described_class.extract("#수업/1학년 메모")).to eq(["수업/1학년"])
      end

      it "하이픈·언더스코어 포함" do
        expect(described_class.extract("#deep_learning #machine-learning")).to eq(%w[deep_learning machine-learning])
      end
    end

    context "거부" do
      it "digit-only는 태그 아님 (#123)" do
        expect(described_class.extract("페이지 #123")).to be_empty
      end

      it "단어 중간 #는 태그 아님 (xy#tag)" do
        expect(described_class.extract("ab#cd")).to be_empty
      end

      it "숫자 뒤 #는 태그 아님 (12#tag)" do
        expect(described_class.extract("12#tag")).to be_empty
      end

      it "# 다음 공백·구두점은 끊김 (마크다운 헤딩 '# 제목'은 추출 안 함)" do
        expect(described_class.extract("# 헤딩이 아님")).to be_empty
      end

      it "단독 #는 무시" do
        expect(described_class.extract("##")).to be_empty
        expect(described_class.extract("# ")).to be_empty
      end
    end

    context "잘못된 입력" do
      it "String이 아니면 빈 배열" do
        expect(described_class.extract(nil)).to eq([])
        expect(described_class.extract(123)).to eq([])
      end
    end

    context "혼합 케이스 (실제 사용자 본문)" do
      it "헤딩과 #태그가 섞여 있어도 #태그만 추출" do
        text = <<~MD
          # 5월 회고

          오늘 #수업 에서 #1학년 학급운영을 다뤘다.
          연구 주제: #classroom-management #협동학습/1단원
        MD
        expect(described_class.extract(text)).to eq(%w[수업 1학년 classroom-management 협동학습/1단원])
      end
    end
  end
end
