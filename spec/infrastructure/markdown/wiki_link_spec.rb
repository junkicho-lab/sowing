# frozen_string_literal: true

RSpec.describe Sowing::Infrastructure::Markdown::WikiLink do
  describe ".extract" do
    context "표준 형식" do
      it "[[target]] 단일 추출" do
        links = described_class.extract("앞 [[다른 노트]] 뒤")
        expect(links.size).to eq(1)
        expect(links.first.target).to eq("다른 노트")
        expect(links.first.display).to eq("다른 노트")
      end

      it "[[target|alias]] alias 분리" do
        links = described_class.extract("[[2026-05-08|오늘]] 회의")
        expect(links.size).to eq(1)
        expect(links.first.target).to eq("2026-05-08")
        expect(links.first.display).to eq("오늘")
      end

      it "본문에 여러 개 섞여있을 때 등장 순서대로" do
        links = described_class.extract("[[A]] 그리고 [[B|별칭]] 또 [[C]]")
        expect(links.map(&:target)).to eq(%w[A B C])
        expect(links.map(&:display)).to eq(["A", "별칭", "C"])
      end

      it "한국어·영문·이모지·공백 target 모두 허용" do
        links = described_class.extract("[[수업 회고 🌱]] [[Lesson 1]]")
        expect(links.map(&:target)).to eq(["수업 회고 🌱", "Lesson 1"])
      end
    end

    context "잘못된 형식 (추출 안 됨)" do
      it "[[]] 빈 target은 무시" do
        expect(described_class.extract("[[]] 뒤")).to be_empty
      end

      it "[[ 만 있고 ]]가 없으면 무시" do
        expect(described_class.extract("[[unclosed")).to be_empty
      end

      it "[[ 안에 ] 또는 [ 가 있으면 무시 (옵시디언과 동일)" do
        expect(described_class.extract("[[a[b]]")).to be_empty
        expect(described_class.extract("[[a]b]]")).to be_empty
      end

      it "단일 [...]는 일반 마크다운 링크 — 무시" do
        expect(described_class.extract("[link](url)")).to be_empty
        expect(described_class.extract("[just text]")).to be_empty
      end

      it "줄바꿈을 가로지르는 위키링크는 매칭하지 않음" do
        expect(described_class.extract("[[part1\npart2]]")).to be_empty
      end
    end

    context "잘못된 입력" do
      it "String이 아니면 빈 배열" do
        expect(described_class.extract(nil)).to eq([])
        expect(described_class.extract(123)).to eq([])
      end
    end
  end

  describe ".transform" do
    it "위키링크를 <a class='wiki-link'>로 치환" do
      out = described_class.transform("앞 [[목표]] 뒤")
      expect(out).to include('<a href="#" class="wiki-link" data-wiki-target="목표">목표</a>')
    end

    it "alias가 있으면 display로 출력하고 data-wiki-target은 target" do
      out = described_class.transform("[[2026-05-08|오늘]]")
      expect(out).to include('data-wiki-target="2026-05-08"')
      expect(out).to include(">오늘</a>")
    end

    it "여러 위키링크를 모두 치환하고 비위키 텍스트는 그대로 유지" do
      out = described_class.transform("처음 [[A]] 가운데 [[B|별칭]] 끝")
      expect(out).to start_with("처음 ")
      expect(out).to include("data-wiki-target=\"A\"")
      expect(out).to include("data-wiki-target=\"B\"")
      expect(out).to include(">별칭</a>")
      expect(out).to end_with(" 끝")
    end

    it "target에 < > & 가 있으면 escape" do
      out = described_class.transform("[[a<b>c|& display]]")
      expect(out).to include("data-wiki-target=\"a&lt;b&gt;c\"")
      expect(out).to include(">&amp; display</a>")
    end

    it "위키링크가 없으면 본문 그대로 유지" do
      expect(described_class.transform("일반 텍스트")).to eq("일반 텍스트")
    end

    it "[[]] 빈 target은 변환하지 않고 원본 보존" do
      expect(described_class.transform("[[]] 빈")).to eq("[[]] 빈")
    end

    it "String이 아니면 to_s로 변환" do
      expect(described_class.transform(nil)).to eq("")
    end
  end

  describe ".render_html" do
    it "기본 형식으로 a 태그를 만든다" do
      html = described_class.render_html(target: "Note", display: nil)
      expect(html).to eq('<a href="#" class="wiki-link" data-wiki-target="Note">Note</a>')
    end

    it "display가 제공되면 표시 텍스트로 사용한다" do
      html = described_class.render_html(target: "Note", display: "별칭")
      expect(html).to eq('<a href="#" class="wiki-link" data-wiki-target="Note">별칭</a>')
    end

    it "display가 빈 문자열이면 target을 표시" do
      html = described_class.render_html(target: "Note", display: "  ")
      expect(html).to include(">Note</a>")
    end
  end

  describe "#new (Value Object)" do
    it "frozen 인스턴스" do
      link = described_class.new(target: "Note")
      expect(link).to be_frozen
      expect(link.target).to be_frozen
      expect(link.display).to be_frozen
    end

    it "display 미지정 시 target과 동일" do
      link = described_class.new(target: "Note")
      expect(link.display).to eq("Note")
    end

    it "target에 양 끝 공백을 strip" do
      link = described_class.new(target: "  Note  ")
      expect(link.target).to eq("Note")
    end

    it "빈 target은 ArgumentError" do
      expect { described_class.new(target: "") }.to raise_error(ArgumentError, /target/)
      expect { described_class.new(target: "  ") }.to raise_error(ArgumentError, /target/)
    end

    it "target이 String이 아니면 ArgumentError" do
      expect { described_class.new(target: nil) }.to raise_error(ArgumentError, /target/)
    end
  end

  describe "#to_markdown (round-trip)" do
    it "alias 없으면 [[target]]" do
      expect(described_class.new(target: "Note").to_markdown).to eq("[[Note]]")
    end

    it "alias 있으면 [[target|display]]" do
      expect(described_class.new(target: "Note", display: "별칭").to_markdown).to eq("[[Note|별칭]]")
    end

    it "extract → to_markdown round-trip이 유지된다" do
      raw = "[[Note]] 와 [[Note|별칭]] 모두 인식"
      links = described_class.extract(raw)
      reconstructed = links.map(&:to_markdown)
      expect(reconstructed).to eq(["[[Note]]", "[[Note|별칭]]"])
    end
  end

  describe "동등성" do
    it "같은 target+display면 ==" do
      a = described_class.new(target: "Note", display: "별칭")
      b = described_class.new(target: "Note", display: "별칭")
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it "Hash 키로 같은 값이 같은 키" do
      a = described_class.new(target: "X")
      b = described_class.new(target: "X")
      h = {a => 1}
      expect(h[b]).to eq(1)
    end
  end
end
