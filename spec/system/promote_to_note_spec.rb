# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "메모 → 필기 승격 (W3-T06)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    FileUtils.rm_rf(vault_dir.join("00_Inbox"))
    FileUtils.rm_rf(vault_dir.join("20_Notes"))
    FileUtils.rm_rf(vault_dir.join(".sowing"))
  end

  def create_memo(body = "오늘 1교시 수업이 활기찼다")
    post "/memos", body: body
    db[:entries].where(mode: "memo").first[:id]
  end

  describe "GET /memos/:id/promote_to_note" do
    let!(:id) { create_memo }

    it "200 OK + 폼 렌더 (제목/카테고리/출처 + 원본 본문 보기)" do
      get "/memos/#{id}/promote_to_note"
      expect(last_response).to be_ok
      expect(last_response.body).to include('id="note_title"')
      expect(last_response.body).to include('id="note_category"')
      expect(last_response.body).to include('id="note_source"')
      expect(last_response.body).to include("원본 메모 본문 보기")
      expect(last_response.body).to include("오늘 1교시 수업이 활기찼다")
    end

    it "form action이 POST /memos/:id/promote_to_note" do
      get "/memos/#{id}/promote_to_note"
      expect(last_response.body).to include(%(action="/memos/#{id}/promote_to_note"))
      expect(last_response.body).to include('method="post"')
    end

    it "카테고리 select에 4개 옵션" do
      get "/memos/#{id}/promote_to_note"
      %w[lessons trainings books meetings].each do |cat|
        expect(last_response.body).to include(%(value="#{cat}"))
      end
    end

    it "없는 id는 404" do
      get "/memos/01XXXXXXXXXXXXXXXXXXXXXXXX/promote_to_note"
      expect(last_response.status).to eq(404)
    end
  end

  describe "POST /memos/:id/promote_to_note (정상)" do
    let!(:id) { create_memo }

    before do
      post "/memos/#{id}/promote_to_note",
        "title" => "1교시 회고",
        "category" => "lessons",
        "source" => "현장 관찰"
    end

    it "/notes/:id로 redirect" do
      expect(last_response.status).to be_between(300, 399)
      expect(last_response.headers["location"]).to end_with("/notes/#{id}")
    end

    it "메모 ID는 유지되고 mode가 note로 갱신" do
      indexed = Sowing::Repositories::IndexRepo.new.find(id)
      expect(indexed.mode).to eq(:note)
    end

    it "옛 00_Inbox 파일은 휴지통, 새 20_Notes/lessons 파일 생성" do
      ts_files = Dir.glob(vault_dir.join("00_Inbox/*.md"))
      expect(ts_files).to be_empty
      expect(vault_dir.join("20_Notes/lessons/1교시 회고.md")).to exist
      trash_files = Dir.glob(vault_dir.join(".sowing/trash/00_Inbox/*.md"))
      expect(trash_files.size).to eq(1)
    end

    it "frontmatter에 promoted_from이 들어간다" do
      content = vault_dir.join("20_Notes/lessons/1교시 회고.md").read
      expect(content).to match(/promoted_from:\s*['"]?00_Inbox\//)
    end

    it "인덱스의 promoted_from도 채워짐" do
      indexed = Sowing::Repositories::IndexRepo.new.find(id)
      expect(indexed.promoted_from).to start_with("00_Inbox/")
    end
  end

  describe "POST /memos/:id/promote_to_note (검증 실패)" do
    let!(:id) { create_memo }

    it "title 비면 422 + 폼 에코" do
      post "/memos/#{id}/promote_to_note",
        "title" => "",
        "category" => "lessons",
        "source" => "출처"
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("제목을 입력")
      expect(last_response.body).to include('value="출처"')
    end

    it "category 외 enum이면 422" do
      post "/memos/#{id}/promote_to_note",
        "title" => "T",
        "category" => "alien",
        "source" => "S"
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("유효하지 않은 카테고리")
    end

    it "source 비면 422" do
      post "/memos/#{id}/promote_to_note",
        "title" => "T",
        "category" => "lessons",
        "source" => ""
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("출처를 입력")
    end

    it "실패 시 메모는 그대로 (인덱스 mode 변화 없음)" do
      post "/memos/#{id}/promote_to_note", "title" => "", "category" => "lessons", "source" => "S"
      expect(Sowing::Repositories::IndexRepo.new.find(id).mode).to eq(:memo)
    end
  end

  describe "POST /memos/:id/promote_to_note (404 분기)" do
    it "없는 id → 404" do
      post "/memos/01XXXXXXXXXXXXXXXXXXXXXXXX/promote_to_note",
        "title" => "T", "category" => "lessons", "source" => "S"
      expect(last_response.status).to eq(404)
    end

    it "Note id로 시도 → 404 (메모 아님)" do
      post "/notes",
        "title" => "필기", "body" => "본문", "category" => "lessons", "source" => "교과서"
      note_id = db[:entries].where(mode: "note").first[:id]
      post "/memos/#{note_id}/promote_to_note",
        "title" => "T", "category" => "lessons", "source" => "S"
      expect(last_response.status).to eq(404)
    end
  end

  describe "메모 카드의 승격 링크" do
    it "/memos 목록 카드에 promote 링크가 있다" do
      id = create_memo
      get "/memos"
      expect(last_response.body).to include("/memos/#{id}/promote_to_note")
    end
  end
end
