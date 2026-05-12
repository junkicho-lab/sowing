# frozen_string_literal: true

require "tmpdir"

# Phase R Stage 4b R4b-T01 — Output::Template (단일 ERB template).
RSpec.describe Sowing::Output::Template do
  let(:tmp_dir) { Pathname.new(Dir.mktmpdir("template-spec-")) }
  let(:erb_path) { tmp_dir.join("student_record.md.erb") }

  before do
    File.write(erb_path, <<~ERB)
      # 학생부

      **대상**: <%= student_name %>
      **작성일**: <%= date %>

      <%= notes || "(미작성)" %>
    ERB
  end

  after { FileUtils.rm_rf(tmp_dir) }

  def build(type: :student_record, format: :markdown, source: nil)
    described_class.new(
      type: type, format: format,
      source_path: erb_path,
      erb_source: source || erb_path.read
    )
  end

  describe ".new" do
    it "type/format 검증 통과 시 frozen 인스턴스" do
      t = build
      expect(t).to be_frozen
      expect(t.type).to eq(:student_record)
      expect(t.format).to eq(:markdown)
    end

    it "TEMPLATE_TYPES 밖 거부" do
      expect { build(type: :unknown) }.to raise_error(ArgumentError, /type/)
    end

    it "FORMATS 밖 거부" do
      expect { build(format: :xml) }.to raise_error(ArgumentError, /format/)
    end
  end

  describe "#render" do
    it "locals 키를 메서드처럼 노출" do
      result = build.render(student_name: "김철수", date: "2026-05-12", notes: "본문")
      expect(result).to include("**대상**: 김철수")
      expect(result).to include("**작성일**: 2026-05-12")
      expect(result).to include("본문")
    end

    it "누락된 locals 키는 nil (NoMethodError 아님)" do
      result = build.render(student_name: "김철수", date: "2026-05-12")
      expect(result).to include("(미작성)") # notes 누락 → || 폴백
    end

    it "locals 이 Hash 가 아니면 ArgumentError" do
      expect { build.render([1, 2]) }.to raise_error(ArgumentError, /Hash/)
    end

    it "trim_mode '-' — <%- -%> 줄바꿈 제거" do
      src = "Hello<%- if name -%>\n, <%= name %>!\n<%- end -%>"
      t = described_class.new(
        type: :student_record, format: :markdown,
        source_path: erb_path, erb_source: src
      )
      expect(t.render(name: "World")).to eq("Hello, World!\n")
    end
  end
end
