# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "충돌 처리 (W5-T05)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    %w[00_Inbox 20_Notes 30_Records .sowing/conflicts].each { |d| FileUtils.rm_rf(vault_dir.join(d)) }
  end

  describe "필기 편집 — 폼 로드" do
    before do
      post "/notes",
        "title" => "원본", "body" => "원본 본문", "category" => "lessons", "source" => "교과서"
    end

    it "edit 폼에 expected_file_hash 숨겨진 입력 포함" do
      note_id = db[:entries].where(mode: "note").first[:id]
      get "/notes/#{note_id}/edit"

      expect(last_response).to be_ok
      expect(last_response.body).to include('name="expected_file_hash"')
    end
  end

  describe "PATCH /notes/:id — 충돌 감지" do
    let(:note_id) { db[:entries].where(mode: "note").first[:id] }
    let(:rel_path) { db[:entries].where(id: note_id).first[:path] }
    let(:abs) { vault_dir.join(rel_path) }

    before do
      post "/notes",
        "title" => "원본", "body" => "원본 본문", "category" => "lessons", "source" => "교과서"
    end

    it "expected_file_hash가 디스크와 일치하면 정상 저장 (302)" do
      current = vault_repo.file_hash(rel_path)
      patch "/notes/#{note_id}",
        "title" => "수정", "body" => "수정 본문", "category" => "lessons",
        "source" => "교과서", "expected_file_hash" => current

      expect(last_response.status).to eq(302)
    end

    it "외부에서 파일이 수정되어 hash 다르면 409 + 충돌 화면 렌더" do
      stale_hash = vault_repo.file_hash(rel_path)
      # 외부 수정 시뮬레이션 — frontmatter 살리고 본문만 교체
      original = abs.read
      File.write(abs, original.sub("원본 본문", "외부에서 먼저 수정한 본문"))

      patch "/notes/#{note_id}",
        "title" => "내가 한 수정", "body" => "내 본문", "category" => "lessons",
        "source" => "교과서", "expected_file_hash" => stale_hash

      expect(last_response.status).to eq(409)
      expect(last_response.body).to include("충돌 감지")
      expect(last_response.body).to include("내가 한 수정")              # mine
      expect(last_response.body).to include("외부에서 먼저 수정한 본문")   # theirs
      expect(last_response.body).to include("Keep Mine")
      expect(last_response.body).to include("Keep Theirs")
      expect(last_response.body).to include('name="force"')
    end

    it "force=1이면 hash 검사 스킵하고 덮어쓰기 + 외부본 .sowing/conflicts/ 백업" do
      stale_hash = vault_repo.file_hash(rel_path)
      original = abs.read
      File.write(abs, original.sub("원본 본문", "외부 수정본"))

      patch "/notes/#{note_id}",
        "title" => "Keep Mine 결과", "body" => "내 본문", "category" => "lessons",
        "source" => "교과서", "expected_file_hash" => stale_hash, "force" => "1"

      expect(last_response.status).to eq(302)

      # 백업 디렉토리에 외부본 보존
      backups = Dir.glob(vault_dir.join(".sowing/conflicts/**/*.md"))
      expect(backups.size).to eq(1)
      expect(File.read(backups.first)).to include("외부 수정본")

      # 인덱스 갱신 — 새 위치(title 변경으로 path 이동)
      reloaded_path = db[:entries].where(id: note_id).first[:path]
      reloaded = vault_repo.read(reloaded_path)
      expect(reloaded.title).to eq("Keep Mine 결과")
    end

    it "expected_file_hash 누락 (옛 폼)이면 충돌 검사 스킵" do
      original = abs.read
      File.write(abs, original.sub("원본 본문", "외부 수정"))

      patch "/notes/#{note_id}",
        "title" => "그냥 저장", "body" => "본문", "category" => "lessons", "source" => "교과서"

      expect(last_response.status).to eq(302)
    end
  end

  describe "PATCH /records/:id — 충돌 감지" do
    let(:record_id) { db[:entries].where(mode: "record").first[:id] }
    let(:rel_path) { db[:entries].where(id: record_id).first[:path] }
    let(:abs) { vault_dir.join(rel_path) }

    before do
      post "/records",
        "title" => "원본 기록", "body" => "원본 본문", "category" => "학급운영"
    end

    it "외부 수정 시 409 + 충돌 화면" do
      stale_hash = vault_repo.file_hash(rel_path)
      File.write(abs, abs.read.sub("원본 본문", "외부 수정본"))

      patch "/records/#{record_id}",
        "title" => "내 수정", "body" => "내 본문", "category" => "학급운영",
        "expected_file_hash" => stale_hash

      expect(last_response.status).to eq(409)
      expect(last_response.body).to include("충돌 감지")
      expect(last_response.body).to include("내 수정")
    end

    it "force=1로 덮어쓰기 + 백업" do
      stale_hash = vault_repo.file_hash(rel_path)
      File.write(abs, abs.read.sub("원본 본문", "외부 수정본"))

      patch "/records/#{record_id}",
        "title" => "Keep Mine", "body" => "내 본문", "category" => "학급운영",
        "expected_file_hash" => stale_hash, "force" => "1"

      expect(last_response.status).to eq(302)
      backups = Dir.glob(vault_dir.join(".sowing/conflicts/**/*.md"))
      expect(backups.size).to eq(1)
    end
  end

  describe "use case 단위 — UpdateNote" do
    let(:use_case) { Sowing::UseCases::UpdateNote.new(vault_repo: vault_repo, index_repo: index_repo) }

    before do
      post "/notes",
        "title" => "원본", "body" => "원본 본문", "category" => "lessons", "source" => "교과서"
    end

    it "Failure([:conflict, payload])에 mine/their 양측 데이터 포함" do
      note_id = db[:entries].where(mode: "note").first[:id]
      rel_path = db[:entries].where(id: note_id).first[:path]
      stale_hash = vault_repo.file_hash(rel_path)
      abs = vault_dir.join(rel_path)
      File.write(abs, abs.read.sub("원본 본문", "외부 수정"))

      result = use_case.call(
        id: note_id, title: "내", body: "내 본문", category: "lessons",
        source: "교과서", expected_file_hash: stale_hash
      )

      expect(result).to be_failure
      tag, payload = result.failure
      expect(tag).to eq(:conflict)
      expect(payload[:mine_title]).to eq("내")
      expect(payload[:their_title]).to eq("원본")
      expect(payload[:their_body]).to include("외부 수정")
      expect(payload[:their_hash]).not_to eq(stale_hash)
    end
  end
end
