# frozen_string_literal: true

require "yaml"

RSpec.describe Sowing::Domain::Record do
  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:tags) { Sowing::Domain::ValueObjects::TagSet.new(["학급운영", "회고"]) }
  let(:created_at) { Time.new(2026, 5, 8, 20, 30, 0, "+09:00") }

  describe ".new" do
    context "필수 인자만 주어졌을 때" do
      subject(:record) { described_class.new(id: ulid, body: "기록 본문", created_at: created_at) }

      it "Record 인스턴스를 만든다" do
        expect(record).to be_a(described_class)
      end

      it "mode는 :record이다" do
        expect(record.mode).to eq(:record)
      end

      it "category·promoted_from은 nil이다" do
        expect(record.category).to be_nil
        expect(record.promoted_from).to be_nil
      end
    end

    context "기록 고유 옵션이 주어졌을 때" do
      subject(:record) {
        described_class.new(
          id: ulid, body: "기록 본문", created_at: created_at,
          title: "5월 학급운영 회고", tags: tags,
          category: "학급운영", promoted_from: "00_Inbox/2026-05-01_153022.md"
        )
      }

      it "category·promoted_from을 노출한다" do
        expect(record.category).to eq("학급운영")
        expect(record.promoted_from).to eq("00_Inbox/2026-05-01_153022.md")
      end
    end

    context "잘못된 입력일 때" do
      let(:valid_args) { {id: ulid, body: "기록", created_at: created_at} }

      it "promoted_from이 String도 nil도 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(promoted_from: 123)) }
          .to raise_error(ArgumentError, /String/)
      end

      it "category가 String도 nil도 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(category: :sym)) }
          .to raise_error(ArgumentError, /String/)
      end
    end
  end

  describe "불변성" do
    let(:record) {
      described_class.new(id: ulid, body: "기록", created_at: created_at,
        category: "학급운영", promoted_from: "00_Inbox/x.md")
    }

    it "인스턴스가 freeze 되어 있다" do
      expect(record).to be_frozen
    end

    it "body·category·promoted_from이 freeze 되어 있다" do
      expect(record.body).to be_frozen
      expect(record.category).to be_frozen
      expect(record.promoted_from).to be_frozen
    end
  end

  describe "#to_frontmatter" do
    context "category·promoted_from이 있을 때" do
      let(:record) {
        described_class.new(
          id: ulid, body: "기록", created_at: created_at,
          title: "5월 회고", tags: tags,
          category: "학급운영", promoted_from: "00_Inbox/2026-05-01_153022.md"
        )
      }

      it "공통 키 + category + promoted_from 를 포함한다" do
        hash = record.to_frontmatter
        expect(hash).to include(
          "id" => ulid.to_s,
          "mode" => "record",
          "title" => "5월 회고",
          "category" => "학급운영",
          "promoted_from" => "00_Inbox/2026-05-01_153022.md"
        )
      end
    end

    context "category·promoted_from이 nil일 때" do
      let(:record) { described_class.new(id: ulid, body: "기록", created_at: created_at) }

      it "두 키 모두 제외된다 (nil 값 키 생략 정책)" do
        hash = record.to_frontmatter
        expect(hash).not_to have_key("category")
        expect(hash).not_to have_key("promoted_from")
      end
    end
  end

  describe "#to_markdown" do
    let(:record) {
      described_class.new(
        id: ulid, body: "올해 학급운영을 돌아본다", created_at: created_at,
        title: "5월 회고", category: "학급운영"
      )
    }

    it "valid frontmatter + body 형식이고 round-trip이 된다" do
      markdown = record.to_markdown
      m = markdown.match(/\A---\n(.*?)\n---\n\n(.*)\z/m)
      hash = YAML.safe_load(m[1])
      expect(hash["mode"]).to eq("record")
      expect(hash["title"]).to eq("5월 회고")
      expect(hash["category"]).to eq("학급운영")
      expect(m[2].chomp).to eq("올해 학급운영을 돌아본다")
    end
  end
end
