# frozen_string_literal: true

require "yaml"

# Phase R Stage 3 R3-T01 — Knowledge::Record 도메인 (Note + Record 흡수).
RSpec.describe Sowing::Knowledge::Record do
  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:tags) { Sowing::Domain::ValueObjects::TagSet.new(["수업", "1학년"]) }
  let(:created_at) { Time.new(2026, 5, 12, 9, 23, 14, "+09:00") }
  let(:updated_at) { Time.new(2026, 5, 12, 10, 0, 0, "+09:00") }

  describe ".new" do
    context "필수 인자만" do
      subject(:record) { described_class.new(id: ulid, body: "본문", created_at: created_at) }

      it "Record 인스턴스 생성" do
        expect(record).to be_a(described_class)
      end

      it "mode 는 :record (Note 폐지, ADR-015)" do
        expect(record.mode).to eq(:record)
      end

      it "category·source·promoted_from·subject 기본값 nil" do
        expect(record.category).to be_nil
        expect(record.source).to be_nil
        expect(record.promoted_from).to be_nil
        expect(record.subject).to be_nil
      end

      it "frozen 불변" do
        expect(record).to be_frozen
        expect(record.body).to be_frozen
      end
    end

    context "Note 호환 — source 부착" do
      subject(:record) {
        described_class.new(
          id: ulid, body: "본문", created_at: created_at,
          source: "https://example.com/article"
        )
      }

      it "source 노출 (옛 Note 의 unique 필드 흡수)" do
        expect(record.source).to eq("https://example.com/article")
      end

      it "to_frontmatter 에 source 키 포함" do
        expect(record.to_frontmatter["source"]).to eq("https://example.com/article")
      end
    end

    context "Record 호환 — category 자유 텍스트" do
      subject(:record) {
        described_class.new(
          id: ulid, body: "본문", created_at: created_at,
          category: "학급운영", title: "1학기 회고"
        )
      }

      it "category 자유 텍스트 그대로" do
        expect(record.category).to eq("학급운영")
      end
    end

    context "subject 4축 (ADR-016)" do
      described_class::SUBJECTS.each do |axis|
        it "subject: #{axis.inspect} 허용" do
          r = described_class.new(id: ulid, body: "본문", created_at: created_at, subject: axis)
          expect(r.subject).to eq(axis)
        end
      end

      it "SUBJECTS 는 Capture::Item::SUBJECTS 와 동일 (DRY)" do
        expect(described_class::SUBJECTS).to eq(Sowing::Capture::Item::SUBJECTS)
      end

      it "임의 Symbol 거부" do
        expect {
          described_class.new(id: ulid, body: "본문", created_at: created_at, subject: :random)
        }.to raise_error(ArgumentError, /subject/)
      end
    end

    context "모든 옵션 인자 (Note+Record 통합)" do
      subject(:record) {
        described_class.new(
          id: ulid, body: "본문", created_at: created_at,
          title: "1학년 1단원 정리", tags: tags, template: "lesson_summary",
          category: "lessons", source: "교과서 p.12",
          promoted_from: "01KR1FE1QYH4EEP6RAGR9DJ6ZK",
          subject: :subject, updated_at: updated_at
        )
      }

      it "모든 속성 그대로 노출" do
        expect(record.title).to eq("1학년 1단원 정리")
        expect(record.tags).to eq(tags)
        expect(record.template).to eq("lesson_summary")
        expect(record.category).to eq("lessons")
        expect(record.source).to eq("교과서 p.12")
        expect(record.promoted_from).to eq("01KR1FE1QYH4EEP6RAGR9DJ6ZK")
        expect(record.subject).to eq(:subject)
        expect(record.updated_at).to eq(updated_at)
      end
    end

    context "validation" do
      it "id 는 ULID 인스턴스" do
        expect { described_class.new(id: "x", body: "y", created_at: created_at) }
          .to raise_error(ArgumentError, /ULID|Ulid/)
      end

      it "body 는 String" do
        expect { described_class.new(id: ulid, body: nil, created_at: created_at) }
          .to raise_error(ArgumentError, /body/)
      end
    end
  end

  describe "#to_frontmatter" do
    it "옵션 nil 키는 .compact 로 제외 (Memo·Record 와 동일 호환)" do
      record = described_class.new(id: ulid, body: "본문", created_at: created_at)
      fm = record.to_frontmatter
      expect(fm).not_to have_key("category")
      expect(fm).not_to have_key("source")
      expect(fm).not_to have_key("promoted_from")
      expect(fm).not_to have_key("subject")
    end

    it "subject 는 Symbol 을 String 으로 직렬화" do
      record = described_class.new(id: ulid, body: "본문", created_at: created_at, subject: :person)
      expect(record.to_frontmatter["subject"]).to eq("person")
    end

    it "공통 7 키 (id/mode/title/tags/template/created_at/updated_at) 포함" do
      record = described_class.new(id: ulid, body: "본문", created_at: created_at)
      fm = record.to_frontmatter
      expect(fm["id"]).to eq(ulid.to_s)
      expect(fm["mode"]).to eq("record")
      expect(fm["created_at"]).to eq(created_at.iso8601)
    end
  end

  describe "#to_markdown" do
    subject(:record) {
      described_class.new(
        id: ulid, body: "본문 내용", created_at: created_at,
        category: "lessons", source: "참고서", subject: :document
      )
    }

    it "옵시디언 호환 (parser 라운드트립)" do
      md = record.to_markdown
      _, frontmatter_str, body = md.split(/^---\n/, 3)
      parsed = YAML.safe_load(frontmatter_str, permitted_classes: [Time, Symbol])
      expect(parsed["id"]).to eq(ulid.to_s)
      expect(parsed["mode"]).to eq("record")
      expect(parsed["category"]).to eq("lessons")
      expect(parsed["source"]).to eq("참고서")
      expect(parsed["subject"]).to eq("document")
      expect(body.strip).to eq("본문 내용")
    end
  end
end
