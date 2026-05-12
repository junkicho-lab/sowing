# frozen_string_literal: true

require "rack/test"
require "fileutils"

# Phase 16 P16-T03 — Archive UI (ADR-017).
RSpec.describe "Archive UI (Phase 16 P16-T03)", type: :request do
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
    FileUtils.rm_rf(Sowing::Core::Paths.vault_dir.join("30_Records"))
  end

  def seed_record(title: "샘플 기록", body: "본문", category: "학생기록")
    use_case = Sowing::UseCases::CreateRecord.new(
      vault_repo: Sowing::Repositories::VaultRepo.new(vault_dir: Sowing::Core::Paths.vault_dir),
      index_repo: Sowing::Repositories::IndexRepo.new
    )
    result = use_case.call(title: title, body: body, category: category, tags: [])
    raise "시드 실패: #{result.failure}" unless result.success?
    result.value!
  end

  describe "POST /records/:id/archive" do
    it "기록을 보관 처리 + /records 로 redirect" do
      record = seed_record(title: "졸업생 기록")
      post "/records/#{record.id}/archive", reason: "2026 졸업"
      expect(last_response.status).to eq(302)

      row = db[:entries].where(id: record.id.to_s).first
      expect(row[:archived_at]).not_to be_nil
      expect(row[:archive_reason]).to eq("2026 졸업")
    end

    it "reason 빈 값 → 기본 사유 '졸업·이관'" do
      record = seed_record
      post "/records/#{record.id}/archive", reason: ""
      row = db[:entries].where(id: record.id.to_s).first
      expect(row[:archive_reason]).to eq("졸업·이관")
    end

    it "존재하지 않는 id → 404" do
      post "/records/01KR1FE1QYH4EEP6RAGR9DJ6ZH/archive", reason: "x"
      expect(last_response.status).to eq(404)
    end
  end

  describe "POST /records/:id/unarchive" do
    it "보관 해제 → /archive 로 redirect + archived_at NULL" do
      record = seed_record
      Sowing::Knowledge.archive(record.id, reason: "test")

      post "/records/#{record.id}/unarchive"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include("/archive")

      row = db[:entries].where(id: record.id.to_s).first
      expect(row[:archived_at]).to be_nil
      expect(row[:archive_reason]).to be_nil
    end
  end

  describe "GET /archive" do
    it "보관된 항목 없으면 빈 안내" do
      get "/archive"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("보관함")
      expect(last_response.body).to include("아직 보관된 항목이 없습니다")
    end

    it "보관된 항목 있으면 목록 표시 + 복원 버튼" do
      r1 = seed_record(title: "졸업1")
      r2 = seed_record(title: "졸업2")
      Sowing::Knowledge.archive(r1.id, reason: "사유A")
      Sowing::Knowledge.archive(r2.id, reason: "사유B")

      get "/archive"
      expect(last_response.body).to include("졸업1")
      expect(last_response.body).to include("졸업2")
      expect(last_response.body).to include("사유A")
      expect(last_response.body).to include("사유B")
      expect(last_response.body).to include("↩ 복원")
    end

    it "복원 후 /archive 에서 사라짐" do
      r = seed_record(title: "임시 보관")
      Sowing::Knowledge.archive(r.id, reason: "실수")
      Sowing::Knowledge.unarchive(r.id)

      get "/archive"
      expect(last_response.body).not_to include("임시 보관")
    end
  end

  describe "보관된 record 는 /records 에서 자동 제외" do
    it "보관 전엔 보이지만 보관 후엔 안 보임 (ADR-017 일상 회상 제외)" do
      r = seed_record(title: "곧 보관될 기록")

      get "/records"
      expect(last_response.body).to include("곧 보관될 기록")

      Sowing::Knowledge.archive(r.id, reason: "x")
      get "/records"
      expect(last_response.body).not_to include("곧 보관될 기록")
    end
  end

  describe "record show 페이지에 보관 버튼" do
    it "📦 보관 form 노출" do
      record = seed_record
      get "/records/#{record.id}"
      expect(last_response.body).to include("📦 보관")
      expect(last_response.body).to include("/archive")
      expect(last_response.body).to include('action="/records/' + record.id.to_s + '/archive"')
    end
  end
end
