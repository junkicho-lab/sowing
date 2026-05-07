# frozen_string_literal: true

require "yaml"

RSpec.describe Sowing::Domain::Memo do
  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:tags) { Sowing::Domain::ValueObjects::TagSet.new(["수업", "1학년"]) }
  let(:created_at) { Time.new(2026, 5, 8, 9, 23, 14, "+09:00") }
  let(:updated_at) { Time.new(2026, 5, 8, 10, 0, 0, "+09:00") }

  describe ".new" do
    context "필수 인자만 주어졌을 때" do
      subject(:memo) { described_class.new(id: ulid, body: "오늘 1교시 수업이 활기찼다", created_at: created_at) }

      it "Memo 인스턴스를 만든다" do
        expect(memo).to be_a(described_class)
      end

      it "mode는 :memo이다" do
        expect(memo.mode).to eq(:memo)
      end

      it "updated_at 기본값은 created_at이다" do
        expect(memo.updated_at).to eq(created_at)
      end

      it "tags 기본값은 빈 TagSet이다" do
        expect(memo.tags).to be_empty
      end

      it "title·template은 nil이다" do
        expect(memo.title).to be_nil
        expect(memo.template).to be_nil
      end
    end

    context "모든 옵션 인자가 주어졌을 때" do
      subject(:memo) {
        described_class.new(
          id: ulid, body: "본문", created_at: created_at,
          title: "오늘 1교시 메모", tags: tags, template: "lesson_reflection",
          updated_at: updated_at
        )
      }

      it "각 속성을 그대로 노출한다" do
        expect(memo.title).to eq("오늘 1교시 메모")
        expect(memo.tags).to eq(tags)
        expect(memo.template).to eq("lesson_reflection")
        expect(memo.updated_at).to eq(updated_at)
      end
    end

    context "잘못된 입력일 때" do
      let(:valid_args) { {id: ulid, body: "본문", created_at: created_at} }

      it "id가 Ulid가 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(id: "01KR1FE1QYH4EEP6RAGR9DJ6ZH")) }
          .to raise_error(ArgumentError, /Ulid/)
      end

      it "body가 String이 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(body: nil)) }.to raise_error(ArgumentError, /String/)
        expect { described_class.new(**valid_args.merge(body: 123)) }.to raise_error(ArgumentError, /String/)
      end

      it "tags가 TagSet이 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(tags: ["수업"])) }
          .to raise_error(ArgumentError, /TagSet/)
      end

      it "created_at이 Time이 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(created_at: "2026-05-08")) }
          .to raise_error(ArgumentError, /Time/)
      end

      it "title이 String도 nil도 아니면 ArgumentError" do
        expect { described_class.new(**valid_args.merge(title: :symbol)) }
          .to raise_error(ArgumentError, /String/)
      end
    end
  end

  describe "불변성" do
    let(:memo) { described_class.new(id: ulid, body: "본문", created_at: created_at) }

    it "인스턴스가 freeze 되어 있다" do
      expect(memo).to be_frozen
    end

    it "body가 freeze 되어 있다" do
      expect(memo.body).to be_frozen
    end
  end

  describe "#to_frontmatter" do
    context "필수 필드만 있을 때" do
      let(:memo) { described_class.new(id: ulid, body: "본문", created_at: created_at) }

      it "필수 키 4개와 tags를 포함한다" do
        hash = memo.to_frontmatter
        expect(hash.keys).to contain_exactly("id", "mode", "tags", "created_at", "updated_at")
      end

      it "nil 값 키(title, template)는 제외된다" do
        hash = memo.to_frontmatter
        expect(hash).not_to have_key("title")
        expect(hash).not_to have_key("template")
      end

      it "id는 String으로, mode는 'memo'로 직렬화된다" do
        hash = memo.to_frontmatter
        expect(hash["id"]).to eq("01KR1FE1QYH4EEP6RAGR9DJ6ZH")
        expect(hash["mode"]).to eq("memo")
      end

      it "created_at은 ISO8601(타임존 포함) 문자열이다" do
        hash = memo.to_frontmatter
        expect(hash["created_at"]).to eq("2026-05-08T09:23:14+09:00")
      end
    end

    context "모든 필드가 있을 때" do
      let(:memo) {
        described_class.new(
          id: ulid, body: "본문", created_at: created_at,
          title: "제목", tags: tags, template: "lesson_reflection", updated_at: updated_at
        )
      }

      it "모든 키를 포함하고 nil은 없다" do
        hash = memo.to_frontmatter
        expect(hash.keys).to contain_exactly(
          "id", "mode", "title", "tags", "template", "created_at", "updated_at"
        )
        expect(hash.values).not_to include(nil)
      end

      it "tags는 정렬된 배열로 직렬화된다 (TagSet 정책)" do
        hash = memo.to_frontmatter
        expect(hash["tags"]).to eq(["1학년", "수업"])
      end
    end
  end

  describe "#to_markdown" do
    let(:memo) { described_class.new(id: ulid, body: "오늘 1교시", created_at: created_at) }
    let(:markdown) { memo.to_markdown }

    it "---로 시작하고 frontmatter 후 빈 줄, 본문, 마지막에 개행이 온다" do
      expect(markdown).to start_with("---\n")
      expect(markdown).to match(/\n---\n\n오늘 1교시\n\z/)
    end

    it "valid YAML frontmatter로 round-trip이 가능하다" do
      m = markdown.match(/\A---\n(.*?)\n---\n\n(.*)\z/m)
      hash = YAML.safe_load(m[1])
      body = m[2].chomp
      expect(hash["id"]).to eq(memo.id.to_s)
      expect(hash["mode"]).to eq("memo")
      expect(body).to eq("오늘 1교시")
    end

    it "body가 줄바꿈으로 끝나도 정확히 한 번의 개행으로 정규화된다" do
      memo = described_class.new(id: ulid, body: "본문\n\n\n", created_at: created_at)
      expect(memo.to_markdown).to end_with("---\n\n본문\n")
    end
  end
end
