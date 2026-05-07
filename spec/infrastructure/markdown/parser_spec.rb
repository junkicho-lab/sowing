# frozen_string_literal: true

RSpec.describe Sowing::Infrastructure::Markdown::Parser do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "정상 frontmatter + body" do
      let(:text) {
        <<~MD
          ---
          id: 01KR1FE1QYH4EEP6RAGR9DJ6ZH
          mode: memo
          created_at: '2026-05-08T09:23:14+09:00'
          tags:
          - 수업
          - 1학년
          ---

          오늘 1교시 수업이 활기찼다
        MD
      }

      it "ParsedDocument를 반환한다" do
        expect(parser.parse(text)).to be_a(Sowing::Infrastructure::Markdown::ParsedDocument)
      end

      it "frontmatter를 Hash로 파싱한다" do
        result = parser.parse(text)
        expect(result.frontmatter).to include(
          "id" => "01KR1FE1QYH4EEP6RAGR9DJ6ZH",
          "mode" => "memo"
        )
      end

      it "한글 태그를 정확히 보존한다" do
        result = parser.parse(text)
        expect(result.frontmatter["tags"]).to eq(["수업", "1학년"])
      end

      it "ISO8601 시간 문자열을 String으로 보존한다 (Time으로 자동 변환되지 않음)" do
        result = parser.parse(text)
        expect(result.frontmatter["created_at"]).to be_a(String)
        expect(result.frontmatter["created_at"]).to eq("2026-05-08T09:23:14+09:00")
      end

      it "body를 String으로 추출한다" do
        result = parser.parse(text)
        expect(result.body).to include("오늘 1교시 수업이 활기찼다")
      end
    end

    context "frontmatter가 없는 경우" do
      it "빈 Hash와 전체 텍스트를 body로 반환한다" do
        result = parser.parse("그냥 본문\n")
        expect(result.frontmatter).to eq({})
        expect(result.body).to eq("그냥 본문\n")
      end
    end

    context "빈 문자열" do
      it "빈 frontmatter와 빈 body를 반환한다" do
        result = parser.parse("")
        expect(result.frontmatter).to eq({})
        expect(result.body).to eq("")
      end
    end

    context "잘못된 입력" do
      it "String이 아니면 ArgumentError" do
        expect { parser.parse(nil) }.to raise_error(ArgumentError, /String/)
        expect { parser.parse(123) }.to raise_error(ArgumentError, /String/)
      end
    end

    context "ParsedDocument 불변성" do
      let(:result) { parser.parse("---\nid: x\n---\n\nbody\n") }

      it "ParsedDocument 인스턴스가 freeze 되어 있다" do
        expect(result).to be_frozen
      end

      it "frontmatter Hash가 freeze 되어 있다" do
        expect(result.frontmatter).to be_frozen
      end

      it "body String이 freeze 되어 있다" do
        expect(result.body).to be_frozen
      end
    end
  end
end
