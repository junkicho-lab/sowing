# frozen_string_literal: true

RSpec.describe Sowing::Infrastructure::Markdown::Serializer do
  let(:serializer) { described_class.new }
  let(:parser) { Sowing::Infrastructure::Markdown::Parser.new }

  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:tags) { Sowing::Domain::ValueObjects::TagSet.new(["수업", "1학년"]) }
  let(:created_at) { Time.new(2026, 5, 8, 9, 23, 14, "+09:00") }

  describe "#serialize" do
    context "Memo를 직렬화할 때" do
      let(:memo) {
        Sowing::Domain::Memo.new(
          id: ulid, body: "오늘 1교시 수업이 활기찼다",
          created_at: created_at, tags: tags, title: "1교시 메모"
        )
      }

      it "도메인의 to_markdown과 동일한 결과를 낸다" do
        expect(serializer.serialize(memo)).to eq(memo.to_markdown)
      end

      it "Parser로 round-trip하면 원래 frontmatter와 일치한다" do
        text = serializer.serialize(memo)
        parsed = parser.parse(text)
        expect(parsed.frontmatter).to eq(memo.to_frontmatter)
      end

      it "Parser로 round-trip하면 원래 body와 일치한다" do
        text = serializer.serialize(memo)
        parsed = parser.parse(text)
        expect(parsed.body.chomp).to eq(memo.body)
      end
    end

    context "Note를 직렬화할 때 (category, source 포함)" do
      let(:note) {
        Sowing::Domain::Note.new(
          id: ulid, body: "협동학습은 ...",
          created_at: created_at, title: "연수 정리",
          category: "trainings", source: "2026 봄 협동학습 연수"
        )
      }

      it "Parser round-trip 후 category·source가 보존된다" do
        text = serializer.serialize(note)
        parsed = parser.parse(text)
        expect(parsed.frontmatter["category"]).to eq("trainings")
        expect(parsed.frontmatter["source"]).to eq("2026 봄 협동학습 연수")
      end
    end

    context "Record를 직렬화할 때 (promoted_from 포함)" do
      let(:record) {
        Sowing::Domain::Record.new(
          id: ulid, body: "5월 회고",
          created_at: created_at, title: "5월 학급운영",
          category: "학급운영", promoted_from: "00_Inbox/2026-05-01_153022.md"
        )
      }

      it "Parser round-trip 후 promoted_from이 보존된다" do
        text = serializer.serialize(record)
        parsed = parser.parse(text)
        expect(parsed.frontmatter["promoted_from"]).to eq("00_Inbox/2026-05-01_153022.md")
      end
    end
  end

  describe "#build" do
    context "Hash + body가 주어졌을 때" do
      let(:frontmatter) {
        {
          "id" => "01KR1FE1QYH4EEP6RAGR9DJ6ZH",
          "mode" => "memo",
          "created_at" => "2026-05-08T09:23:14+09:00",
          "tags" => ["수업"]
        }
      }

      it "valid 마크다운(frontmatter + body) 문자열을 반환한다" do
        text = serializer.build(frontmatter, "본문")
        expect(text).to start_with("---\n")
        expect(text).to end_with("---\n\n본문\n")
      end

      it "Parser로 round-trip하면 동일한 Hash를 얻는다" do
        text = serializer.build(frontmatter, "본문")
        parsed = parser.parse(text)
        expect(parsed.frontmatter).to eq(frontmatter)
      end

      it "body의 trailing 개행은 정확히 한 개로 정규화된다" do
        text = serializer.build(frontmatter, "본문\n\n\n")
        expect(text).to end_with("---\n\n본문\n")
      end

      it "빈 body도 처리한다" do
        text = serializer.build(frontmatter, "")
        expect(text).to end_with("---\n\n\n")
      end
    end

    context "잘못된 입력" do
      it "frontmatter가 Hash가 아니면 ArgumentError" do
        expect { serializer.build("not a hash", "body") }.to raise_error(ArgumentError, /Hash/)
      end

      it "body가 String이 아니면 ArgumentError" do
        expect { serializer.build({}, nil) }.to raise_error(ArgumentError, /String/)
      end
    end
  end

  describe "Serializer ↔ Parser 일관성" do
    it "Memo의 #serialize와 #build(frontmatter, body)는 동일한 결과" do
      memo = Sowing::Domain::Memo.new(id: ulid, body: "x", created_at: created_at)
      via_serialize = serializer.serialize(memo)
      via_build = serializer.build(memo.to_frontmatter, memo.body)
      expect(via_serialize).to eq(via_build)
    end
  end
end
