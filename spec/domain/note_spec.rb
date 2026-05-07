# frozen_string_literal: true

require "yaml"

RSpec.describe Sowing::Domain::Note do
  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:tags) { Sowing::Domain::ValueObjects::TagSet.new(["연수", "협동학습"]) }
  let(:created_at) { Time.new(2026, 5, 8, 14, 0, 0, "+09:00") }

  describe ".new" do
    context "필수 인자만 주어졌을 때" do
      subject(:note) { described_class.new(id: ulid, body: "필기 본문", created_at: created_at) }

      it "Note 인스턴스를 만든다" do
        expect(note).to be_a(described_class)
      end

      it "mode는 :note이다" do
        expect(note.mode).to eq(:note)
      end

      it "category·source는 nil이다" do
        expect(note.category).to be_nil
        expect(note.source).to be_nil
      end
    end

    context "필기 고유 옵션이 주어졌을 때" do
      subject(:note) {
        described_class.new(
          id: ulid, body: "필기 본문", created_at: created_at,
          title: "협동학습 연수 정리", tags: tags,
          category: "trainings", source: "2026 봄 협동학습 연수"
        )
      }

      it "category·source를 노출한다" do
        expect(note.category).to eq("trainings")
        expect(note.source).to eq("2026 봄 협동학습 연수")
      end
    end

    context "잘못된 입력일 때" do
      let(:valid_args) { {id: ulid, body: "필기", created_at: created_at} }

      it "category가 String도 nil도 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(category: 123)) }
          .to raise_error(ArgumentError, /String/)
      end

      it "source가 String도 nil도 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(source: :sym)) }
          .to raise_error(ArgumentError, /String/)
      end

      it "id가 Ulid가 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(id: "raw-string")) }
          .to raise_error(ArgumentError, /Ulid/)
      end
    end
  end

  describe "불변성" do
    let(:note) {
      described_class.new(id: ulid, body: "필기", created_at: created_at,
        category: "lessons", source: "교과서 1단원")
    }

    it "인스턴스가 freeze 되어 있다" do
      expect(note).to be_frozen
    end

    it "body·category·source가 freeze 되어 있다" do
      expect(note.body).to be_frozen
      expect(note.category).to be_frozen
      expect(note.source).to be_frozen
    end
  end

  describe "#to_frontmatter" do
    context "category·source가 있을 때" do
      let(:note) {
        described_class.new(
          id: ulid, body: "필기", created_at: created_at,
          title: "1단원 정리", tags: tags,
          category: "lessons", source: "교과서 1단원"
        )
      }

      it "공통 키 + category + source 를 포함한다" do
        hash = note.to_frontmatter
        expect(hash).to include(
          "id" => ulid.to_s,
          "mode" => "note",
          "title" => "1단원 정리",
          "category" => "lessons",
          "source" => "교과서 1단원"
        )
      end
    end

    context "category·source가 nil일 때" do
      let(:note) { described_class.new(id: ulid, body: "필기", created_at: created_at) }

      it "category·source 키는 제외된다 (nil 값 키 생략 정책)" do
        hash = note.to_frontmatter
        expect(hash).not_to have_key("category")
        expect(hash).not_to have_key("source")
      end
    end
  end

  describe "#to_markdown" do
    let(:note) {
      described_class.new(
        id: ulid, body: "협동학습은 ...", created_at: created_at,
        category: "trainings", source: "연수 자료집"
      )
    }

    it "valid frontmatter + body 형식이고 round-trip이 된다" do
      markdown = note.to_markdown
      m = markdown.match(/\A---\n(.*?)\n---\n\n(.*)\z/m)
      hash = YAML.safe_load(m[1])
      expect(hash["mode"]).to eq("note")
      expect(hash["category"]).to eq("trainings")
      expect(hash["source"]).to eq("연수 자료집")
      expect(m[2].chomp).to eq("협동학습은 ...")
    end
  end
end
