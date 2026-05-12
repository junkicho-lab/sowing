# frozen_string_literal: true

require "rack/test"
require "fileutils"

# Phase 16 P16-T01 — 기존 record/note 의 마크다운·PDF·DOCX 내보내기.
RSpec.describe "Export UI (Phase 16 P16-T01)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete

    vault = Sowing::Core::Paths.vault_dir
    FileUtils.rm_rf(vault.join("30_Records"))
    FileUtils.rm_rf(vault.join("20_Notes"))
  end

  # ── 시드 helper ─────────────────────────────────────────────
  def create_record(title: "2026 1학기 회고", body: "올해 1학기는 활기찼다.\n\n학생들이 적극적이었다.", category: "학기회고")
    use_case = Sowing::UseCases::CreateRecord.new(
      vault_repo: Sowing::Repositories::VaultRepo.new(vault_dir: Sowing::Core::Paths.vault_dir),
      index_repo: Sowing::Repositories::IndexRepo.new
    )
    result = use_case.call(title: title, body: body, category: category, tags: [])
    raise "시드 실패: #{result.failure}" unless result.success?
    result.value!
  end

  describe "GET /records/:id/export?format=markdown" do
    it "마크다운 본문 반환 (200 + text/markdown)" do
      record = create_record(title: "5월 회고", body: "5월은 학생회 활동이 많았다.")
      get "/records/#{record.id}/export?format=markdown"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("text/markdown")
      expect(last_response.body).to include("# 5월 회고")
      expect(last_response.body).to include("5월은 학생회 활동이 많았다.")
    end

    it "Content-Disposition attachment + UTF-8 한글 파일명" do
      record = create_record(title: "교사 성찰")
      get "/records/#{record.id}/export?format=markdown"
      disp = last_response.headers["Content-Disposition"]
      expect(disp).to include("attachment")
      expect(disp).to include("filename*=UTF-8''")
      expect(disp).to include(".md")
    end
  end

  describe "GET /records/:id/export?format=pdf" do
    it "PDF binary 반환 (%PDF magic, application/pdf)" do
      record = create_record(title: "PDF 테스트")
      get "/records/#{record.id}/export?format=pdf"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to eq("application/pdf")
      expect(last_response.body[0, 4]).to eq("%PDF")
    end

    it ".pdf 확장자가 Content-Disposition 에 포함" do
      record = create_record(title: "x")
      get "/records/#{record.id}/export?format=pdf"
      expect(last_response.headers["Content-Disposition"]).to include(".pdf")
    end
  end

  describe "GET /records/:id/export?format=docx" do
    it "DOCX binary 반환 (ZIP magic, OOXML content-type)" do
      record = create_record(title: "DOCX 테스트")
      get "/records/#{record.id}/export?format=docx"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to eq(
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      )
      expect(last_response.body[0, 2].bytes).to eq([0x50, 0x4B]) # ZIP magic
    end
  end

  describe "format 검증" do
    it "지원 외 format 은 400" do
      record = create_record
      get "/records/#{record.id}/export?format=xml"
      expect(last_response.status).to eq(400)
    end

    it "format 미지정 → markdown default" do
      record = create_record
      get "/records/#{record.id}/export"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("text/markdown")
    end
  end

  describe "404 — 없는 id" do
    it "유효 ULID 지만 미존재 → 404" do
      get "/records/01KR1FE1QYH4EEP6RAGR9DJ6ZH/export?format=pdf"
      expect(last_response.status).to eq(404)
    end
  end

  describe "내보내기 버튼이 show 페이지에 노출됨" do
    it "기록 show 에 3 형식 모두 링크" do
      record = create_record
      get "/records/#{record.id}"
      expect(last_response.body).to include("📥 내보내기")
      expect(last_response.body).to include("export?format=markdown")
      expect(last_response.body).to include("export?format=pdf")
      expect(last_response.body).to include("export?format=docx")
    end
  end
end
