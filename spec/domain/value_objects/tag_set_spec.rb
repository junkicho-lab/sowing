# frozen_string_literal: true

RSpec.describe Sowing::Domain::ValueObjects::TagSet do
  describe ".new" do
    context "유효한 태그 배열일 때" do
      it "정렬되고 중복 제거된 TagSet을 만든다" do
        tags = described_class.new(["수학", "수업", "수학"])
        expect(tags.to_a).to eq(["수업", "수학"])
      end

      it "공백을 strip하고 소문자로 정규화한다" do
        tags = described_class.new(["  Math  ", "MATH", "math"])
        expect(tags.to_a).to eq(["math"])
      end

      it "한국어·영문·숫자 태그가 모두 정규화된다" do
        tags = described_class.new(["수학", "1학년", "수업", "MATH"])
        expect(tags.to_a).to eq(["1학년", "math", "수업", "수학"])
      end

      it "빈 배열을 허용한다 (빈 TagSet)" do
        expect(described_class.new([])).to be_empty
      end

      it "기본값(인자 없음)이면 빈 TagSet이다" do
        expect(described_class.new).to be_empty
      end
    end

    context "잘못된 입력일 때" do
      it "Array가 아니면 ArgumentError" do
        expect { described_class.new("수업") }.to raise_error(ArgumentError, /Array/)
        expect { described_class.new(nil) }.to raise_error(ArgumentError, /Array/)
      end

      it "원소가 String이 아니면 ArgumentError" do
        expect { described_class.new(["수업", :symbol]) }.to raise_error(ArgumentError, /String/)
        expect { described_class.new([1, 2]) }.to raise_error(ArgumentError, /String/)
        expect { described_class.new([nil]) }.to raise_error(ArgumentError, /String/)
      end

      it "빈 문자열을 포함하면 ArgumentError" do
        expect { described_class.new(["수업", ""]) }.to raise_error(ArgumentError, /빈 태그/)
      end

      it "공백만 있는 문자열을 포함하면 ArgumentError" do
        expect { described_class.new(["수업", "   "]) }.to raise_error(ArgumentError, /빈 태그/)
      end
    end
  end

  describe "불변성" do
    let(:tags) { described_class.new(["수업", "수학"]) }

    it "인스턴스가 freeze 되어 있다" do
      expect(tags).to be_frozen
    end

    it "to_a 결과(내부 배열)도 freeze 되어 있다" do
      expect(tags.to_a).to be_frozen
    end

    it "to_a 결과를 변경하려 하면 FrozenError" do
      expect { tags.to_a << "강제" }.to raise_error(FrozenError)
    end
  end

  describe "동등성" do
    it "같은 정규화 결과이면 == 이다 (입력 순서 무관)" do
      a = described_class.new(["수업", "수학"])
      b = described_class.new(["수학", "수업"])
      expect(a).to eq(b)
    end

    it "공백·대소문자 차이가 있어도 정규화 후 같으면 == 이다" do
      a = described_class.new(["MATH"])
      b = described_class.new(["  math  "])
      expect(a).to eq(b)
    end

    it "다른 태그면 != 이다" do
      a = described_class.new(["수업"])
      b = described_class.new(["수학"])
      expect(a).not_to eq(b)
    end

    it "다른 클래스(예: 배열)와는 != 이다" do
      tags = described_class.new(["수업"])
      expect(tags).not_to eq(["수업"])
    end

    it "Hash 키로 사용 시 같은 값이 같은 키로 동작한다" do
      a = described_class.new(["수업"])
      b = described_class.new(["수업"])
      h = {a => :one}
      expect(h[b]).to eq(:one)
    end

    it "eql? 도 동등성을 만족한다" do
      a = described_class.new(["수업"])
      b = described_class.new(["수업"])
      expect(a.eql?(b)).to be true
    end
  end

  describe "컬렉션 인터페이스" do
    let(:tags) { described_class.new(["수학", "수업", "1학년"]) }

    it "#to_a는 정렬된 태그 배열을 반환한다" do
      expect(tags.to_a).to eq(["1학년", "수업", "수학"])
    end

    it "#size·#length는 태그 개수를 반환한다" do
      expect(tags.size).to eq(3)
      expect(tags.length).to eq(3)
    end

    it "#include? 는 정규화된 형태로 검사한다" do
      expect(tags.include?("수업")).to be true
      expect(tags.include?("  수업  ")).to be true
      expect(tags.include?("국어")).to be false
    end

    it "#include? 는 String 외 타입에 대해 false를 반환한다" do
      expect(tags.include?(:수업)).to be false
      expect(tags.include?(nil)).to be false
    end

    it "#empty? 는 빈 TagSet에서 true이고, 비어있지 않으면 false다" do
      expect(described_class.new).to be_empty
      expect(tags).not_to be_empty
    end

    it "#each는 정렬된 순서로 yield 한다" do
      yielded = []
      tags.each { |t| yielded << t }
      expect(yielded).to eq(["1학년", "수업", "수학"])
    end
  end
end
