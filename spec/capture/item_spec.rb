# frozen_string_literal: true

require "yaml"

# Phase R Stage 2 R2-T01 — Capture::Item 도메인 모델.
# 옛 Domain::Memo 와 호환 (mode :memo 유지) + subject 4축 추가.
RSpec.describe Sowing::Capture::Item do
  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:tags) { Sowing::Domain::ValueObjects::TagSet.new(["수업", "1학년"]) }
  let(:created_at) { Time.new(2026, 5, 12, 9, 23, 14, "+09:00") }
  let(:updated_at) { Time.new(2026, 5, 12, 10, 0, 0, "+09:00") }

  describe ".new" do
    context "필수 인자만 주어졌을 때" do
      subject(:item) { described_class.new(id: ulid, body: "오늘 1교시 수업", created_at: created_at) }

      it "Item 인스턴스를 만든다" do
        expect(item).to be_a(described_class)
      end

      it "mode 는 :memo (Strangler Fig 호환)" do
        expect(item.mode).to eq(:memo)
      end

      it "subject 기본값은 nil (4축 선택적)" do
        expect(item.subject).to be_nil
      end

      it "updated_at 기본값은 created_at" do
        expect(item.updated_at).to eq(created_at)
      end

      it "title·template·tags 기본값" do
        expect(item.title).to be_nil
        expect(item.template).to be_nil
        expect(item.tags).to be_empty
      end

      it "frozen 되어 있다" do
        expect(item).to be_frozen
        expect(item.body).to be_frozen
      end
    end

    context "subject 4축 — 유효 값" do
      Sowing::Capture::Item::SUBJECTS.each do |axis|
        it "subject: #{axis.inspect} 를 받아들인다" do
          item = described_class.new(id: ulid, body: "본문", created_at: created_at, subject: axis)
          expect(item.subject).to eq(axis)
        end
      end
    end

    context "subject — 유효하지 않은 값" do
      it "임의 Symbol 거부" do
        expect {
          described_class.new(id: ulid, body: "본문", created_at: created_at, subject: :random)
        }.to raise_error(ArgumentError, /subject/)
      end

      it "String 거부 (Symbol 만 허용)" do
        expect {
          described_class.new(id: ulid, body: "본문", created_at: created_at, subject: "person")
        }.to raise_error(ArgumentError, /subject/)
      end
    end

    context "모든 옵션 인자가 주어졌을 때" do
      subject(:item) {
        described_class.new(
          id: ulid, body: "본문", created_at: created_at,
          title: "수업 메모", tags: tags, template: "lesson_reflection",
          subject: :subject, updated_at: updated_at
        )
      }

      it "각 속성을 그대로 노출" do
        expect(item.title).to eq("수업 메모")
        expect(item.tags).to eq(tags)
        expect(item.template).to eq("lesson_reflection")
        expect(item.subject).to eq(:subject)
        expect(item.updated_at).to eq(updated_at)
      end
    end

    context "validation" do
      it "id 는 ULID 인스턴스여야 함" do
        expect { described_class.new(id: "string", body: "x", created_at: created_at) }
          .to raise_error(ArgumentError, /ULID|Ulid/)
      end

      it "body 는 String 이어야 함" do
        expect { described_class.new(id: ulid, body: nil, created_at: created_at) }
          .to raise_error(ArgumentError, /body/)
      end

      it "created_at 는 Time 이어야 함" do
        expect { described_class.new(id: ulid, body: "x", created_at: "2026-05-12") }
          .to raise_error(ArgumentError, /created_at/)
      end
    end
  end

  describe "#to_frontmatter" do
    context "subject 없는 경우 (옛 Memo 와 동일)" do
      subject(:item) { described_class.new(id: ulid, body: "본문", created_at: created_at) }

      it "subject 키 자체가 누락 (.compact)" do
        expect(item.to_frontmatter).not_to have_key("subject")
      end

      it "공통 키 보유" do
        fm = item.to_frontmatter
        expect(fm["id"]).to eq(ulid.to_s)
        expect(fm["mode"]).to eq("memo")
        expect(fm["created_at"]).to eq(created_at.iso8601)
      end
    end

    context "subject 있는 경우" do
      subject(:item) {
        described_class.new(id: ulid, body: "본문", created_at: created_at, subject: :person)
      }

      it "subject 키가 String 으로 저장됨" do
        expect(item.to_frontmatter["subject"]).to eq("person")
      end
    end
  end

  describe "#to_markdown" do
    subject(:item) {
      described_class.new(id: ulid, body: "본문", created_at: created_at, subject: :document)
    }

    it "YAML frontmatter + 빈 줄 + body 형식" do
      md = item.to_markdown
      expect(md).to start_with("---\n")
      expect(md).to include("subject: document")
      expect(md).to end_with("본문\n")
    end

    it "옵시디언 호환 (parser 로 재읽기 가능)" do
      md = item.to_markdown
      _, frontmatter_str, body = md.split(/^---\n/, 3)
      parsed = YAML.safe_load(frontmatter_str, permitted_classes: [Time, Symbol])
      expect(parsed["id"]).to eq(ulid.to_s)
      expect(parsed["mode"]).to eq("memo")
      expect(parsed["subject"]).to eq("document")
      expect(body.strip).to eq("본문")
    end
  end
end
