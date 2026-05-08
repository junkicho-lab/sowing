# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "필기 편집 (GET /notes/:id/edit, PATCH /notes/:id)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    FileUtils.rm_rf(vault_dir.join("20_Notes"))
    FileUtils.rm_rf(vault_dir.join(".sowing"))
  end

  def create_note_form(form = {})
    {
      "title" => "원본 제목",
      "body" => "원본 본문",
      "category" => "lessons",
      "source" => "교과서",
      "tags" => "수업, 1학년"
    }.merge(form)
  end

  def post_create(form = {})
    post "/notes", create_note_form(form)
    db[:entries].first[:id]
  end

  describe "GET /notes/:id/edit" do
    let!(:id) { post_create }

    it "200 OK + 폼이 기존 값으로 prefill 된다" do
      get "/notes/#{id}/edit"
      expect(last_response).to be_ok
      expect(last_response.body).to include('value="원본 제목"')
      expect(last_response.body).to include('value="교과서"')
      expect(last_response.body).to include("원본 본문")
      # TagSet 정책에 따라 strip+downcase+sort된 형태로 prefill (입력 "수업, 1학년" → "1학년, 수업")
      expect(last_response.body).to include("1학년, 수업")
    end

    it "선택된 카테고리에 selected 속성이 들어간다" do
      get "/notes/#{id}/edit"
      expect(last_response.body).to match(/<option value="lessons" selected>수업/)
    end

    it "form이 PATCH로 동작한다 (_method hidden)" do
      get "/notes/#{id}/edit"
      expect(last_response.body).to include('name="_method" value="patch"')
      expect(last_response.body).to include(%(action="/notes/#{id}"))
    end

    it "없는 id는 404" do
      get "/notes/01XXXXXXXXXXXXXXXXXXXXXXXX/edit"
      expect(last_response.status).to eq(404)
    end
  end

  describe "PATCH /notes/:id (정상)" do
    let!(:id) { post_create }

    it "/notes/:id 로 redirect 한다" do
      patch "/notes/#{id}", create_note_form("body" => "수정된 본문")
      expect(last_response.status).to be_between(300, 399)
      expect(last_response.headers["location"]).to end_with("/notes/#{id}")
    end

    it "본문만 바꾸면 같은 path에 atomic 덮어쓰기 (휴지통 비어있음)" do
      patch "/notes/#{id}", create_note_form("body" => "수정된 본문")
      expect(vault_dir.join("20_Notes/lessons/원본 제목.md").read).to include("수정된 본문")
      expect(vault_dir.join(".sowing/trash").exist?).to be false
    end

    it "title 변경 시 새 path에 쓰고 옛 파일은 휴지통으로" do
      patch "/notes/#{id}", create_note_form("title" => "수정된 제목")
      expect(vault_dir.join("20_Notes/lessons/수정된 제목.md")).to exist
      expect(vault_dir.join("20_Notes/lessons/원본 제목.md")).not_to exist
      expect(vault_dir.join(".sowing/trash/20_Notes/lessons/원본 제목.md")).to exist
    end

    it "category 변경 시 새 디렉토리에 쓰고 옛 위치는 휴지통으로" do
      patch "/notes/#{id}", create_note_form("category" => "trainings")
      expect(vault_dir.join("20_Notes/trainings/원본 제목.md")).to exist
      expect(vault_dir.join("20_Notes/lessons/원본 제목.md")).not_to exist
    end

    it "인덱스가 새 path로 갱신된다" do
      patch "/notes/#{id}", create_note_form("title" => "수정된 제목")
      row = db[:entries].where(id: id).first
      expect(row[:path]).to eq("20_Notes/lessons/수정된 제목.md")
      expect(row[:title]).to eq("수정된 제목")
    end
  end

  describe "PATCH /notes/:id (검증 실패)" do
    let!(:id) { post_create }

    it "title 비면 422 + 폼 + 메시지" do
      patch "/notes/#{id}", create_note_form("title" => "")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("제목을 입력")
    end

    it "category enum 외면 422" do
      patch "/notes/#{id}", create_note_form("category" => "alien")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("유효하지 않은 카테고리")
    end

    it "source 비면 422" do
      patch "/notes/#{id}", create_note_form("source" => "")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("출처를 입력")
    end

    it "실패 시 입력값을 폼에 다시 채워 넣는다" do
      patch "/notes/#{id}", create_note_form("title" => "임시 제목", "body" => "")
      expect(last_response.body).to include('value="임시 제목"')
    end

    it "실패 시 파일·인덱스는 변경되지 않는다" do
      original_body = vault_dir.join("20_Notes/lessons/원본 제목.md").read
      patch "/notes/#{id}", create_note_form("title" => "임시", "body" => "")
      expect(vault_dir.join("20_Notes/lessons/원본 제목.md").read).to eq(original_body)
    end
  end

  describe "PATCH /notes/:id (404 분기)" do
    it "없는 id는 404" do
      patch "/notes/01XXXXXXXXXXXXXXXXXXXXXXXX", create_note_form
      expect(last_response.status).to eq(404)
    end

    it "다른 mode의 id는 404" do
      post "/memos", body: "메모"
      memo_id = db[:entries].where(mode: "memo").first[:id]
      patch "/notes/#{memo_id}", create_note_form
      expect(last_response.status).to eq(404)
    end
  end

  describe "show 페이지의 편집 버튼" do
    it "/notes/:id에 '편집' 링크가 있다" do
      id = post_create
      get "/notes/#{id}"
      expect(last_response.body).to include("/notes/#{id}/edit")
      expect(last_response.body).to include(">편집<")
    end
  end
end
