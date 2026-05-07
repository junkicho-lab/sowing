# frozen_string_literal: true

RSpec.describe Sowing::Domain::ValueObjects::Ulid do
  describe ".generate" do
    context "인자 없이 호출할 때" do
      it "Ulid 인스턴스를 반환한다" do
        expect(described_class.generate).to be_a(described_class)
      end

      it "26자 문자열 값을 가진다" do
        expect(described_class.generate.to_s.length).to eq(26)
      end

      it "두 번 호출하면 서로 다른 ULID를 반환한다" do
        a = described_class.generate
        b = described_class.generate
        expect(a).not_to eq(b)
      end

      it "시간순으로 단조 증가한다 (사전순 비교)" do
        a = described_class.generate
        sleep(0.002)
        b = described_class.generate
        expect(a).to be < b
      end

      it "Crockford Base32 형식을 만족한다" do
        20.times do
          expect(described_class.generate.to_s).to match(/\A[0-9A-HJKMNP-TV-Z]{26}\z/)
        end
      end
    end
  end

  describe ".parse" do
    let(:raw) { "01KR1FE1QYH4EEP6RAGR9DJ6ZH" }

    context "유효한 ULID 문자열일 때" do
      it "동일한 값의 인스턴스를 반환한다" do
        expect(described_class.parse(raw).to_s).to eq(raw)
      end

      it "소문자 입력을 대문자로 정규화한다" do
        expect(described_class.parse(raw.downcase).to_s).to eq(raw)
      end
    end

    context "잘못된 입력일 때" do
      it "문자열이 아니면 ArgumentError" do
        expect { described_class.parse(nil) }.to raise_error(ArgumentError, /String/)
        expect { described_class.parse(123) }.to raise_error(ArgumentError, /String/)
      end

      it "26자가 아니면 ArgumentError" do
        expect { described_class.parse("01KR1FE1QY") }.to raise_error(ArgumentError, /형식/)
        expect { described_class.parse("0" * 27) }.to raise_error(ArgumentError, /형식/)
        expect { described_class.parse("") }.to raise_error(ArgumentError, /형식/)
      end

      it "Crockford Base32 외 문자(I/L/O/U)는 거부한다" do
        bad_chars = %w[I L O U]
        bad_chars.each do |ch|
          bad = "01KR1FE1QYH4EEP6RAGR9DJ6Z#{ch}"
          expect { described_class.parse(bad) }.to raise_error(ArgumentError, /형식/)
        end
      end
    end
  end

  describe "불변성" do
    let(:ulid) { described_class.generate }

    it "인스턴스가 freeze 되어 있다" do
      expect(ulid).to be_frozen
    end

    it "내부 value 문자열도 freeze 되어 있다" do
      expect(ulid.value).to be_frozen
    end
  end

  describe "동등성·정렬" do
    let(:a) { described_class.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
    let(:a_dup) { described_class.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
    let(:b) { described_class.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZJ") }

    it "같은 값이면 == 가 true이다" do
      expect(a).to eq(a_dup)
    end

    it "다른 값이면 == 가 false이다" do
      expect(a).not_to eq(b)
    end

    it "다른 클래스(예: 문자열)와는 == 가 false이다" do
      expect(a).not_to eq("01KR1FE1QYH4EEP6RAGR9DJ6ZH")
    end

    it "<=> 로 사전순 비교가 가능하다" do
      expect(a <=> b).to eq(-1)
      expect(b <=> a).to eq(1)
      expect(a <=> a_dup).to eq(0)
    end

    it "다른 클래스와의 <=> 는 nil을 반환한다" do
      expect(a <=> "string").to be_nil
    end

    it "Hash 키로 사용 시 같은 값이 같은 키로 동작한다" do
      h = {a => :one}
      expect(h[a_dup]).to eq(:one)
    end

    it "eql? 도 동등성을 만족한다" do
      expect(a.eql?(a_dup)).to be true
      expect(a.eql?(b)).to be false
    end

    it "Comparable의 between? 가 동작한다" do
      expect(a.between?(a, b)).to be true
    end
  end

  describe "#to_s" do
    it "26자 ULID 문자열을 반환한다" do
      ulid = described_class.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH")
      expect(ulid.to_s).to eq("01KR1FE1QYH4EEP6RAGR9DJ6ZH")
    end
  end
end
