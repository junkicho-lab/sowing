# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "필기 라우트", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    FileUtils.rm_rf(vault_dir.join("20_Notes"))
  end

  def valid_form
    {
      "title" => "1단원 정리",
      "body" => "오늘 배운 내용을 정리한다.",
      "category" => "lessons",
      "source" => "교과서 1단원",
      "tags" => "수업, 1학년"
    }
  end

  describe "GET /notes (빈 상태)" do
    before { get "/notes" }

    it "200 OK + 카테고리 4개 필터 탭이 보인다" do
      expect(last_response).to be_ok
      %w[전체 수업 연수 도서 회의].each { |label| expect(last_response.body).to include(label) }
    end

    it "총 0건 + 첫 필기 작성 CTA가 보인다" do
      expect(last_response.body).to include("총 0건")
      expect(last_response.body).to include("+ 첫 필기 작성하기")
    end

    it "+ 새 필기 버튼이 /notes/new를 가리킨다" do
      expect(last_response.body).to include('href="/notes/new"')
    end
  end

  describe "GET /notes/new (폼)" do
    before { get "/notes/new" }

    it "필수 필드 입력 폼을 렌더한다" do
      expect(last_response).to be_ok
      expect(last_response.body).to include('<input type="text"')
      expect(last_response.body).to include('id="note_title"')
      expect(last_response.body).to include('id="note_category"')
      expect(last_response.body).to include('id="note_source"')
      expect(last_response.body).to include('id="note_body"')
    end

    it "카테고리 select에 4개 옵션이 들어 있다 (한국어 라벨)" do
      expect(last_response.body).to include('value="lessons"')
      expect(last_response.body).to include(">수업<")
      expect(last_response.body).to include('value="trainings"')
      expect(last_response.body).to include(">연수<")
      expect(last_response.body).to include('value="books"')
      expect(last_response.body).to include(">도서<")
      expect(last_response.body).to include('value="meetings"')
      expect(last_response.body).to include(">회의<")
    end

    it "submit form action이 POST /notes다" do
      expect(last_response.body).to include('action="/notes"')
      expect(last_response.body).to include('method="post"')
    end
  end

  describe "POST /notes (정상)" do
    before { post "/notes", valid_form }

    it "/notes로 redirect한다 (303 또는 302)" do
      expect(last_response.status).to be_between(300, 399)
      expect(last_response.headers["location"]).to end_with("/notes")
    end

    it "마크다운 파일이 20_Notes/lessons/{title}.md에 생성된다" do
      expect(vault_dir.join("20_Notes/lessons/1단원 정리.md")).to exist
    end

    it "SQLite 인덱스에 row가 추가되고 mode·category가 기록된다" do
      expect(db[:entries].count).to eq(1)
      row = db[:entries].first
      expect(row[:mode]).to eq("note")
      expect(row[:category]).to eq("lessons")
    end

    it "tags가 정규화되어 인덱스에 들어간다 (공백·쉼표 분리)" do
      expect(db[:tags].count).to eq(2)
      names = db[:tags].order(:name).map(:name)
      expect(names).to include("수업", "1학년")
    end
  end

  describe "POST /notes (검증 실패)" do
    it "title이 비면 422 + '제목을 입력해 주세요' 메시지" do
      post "/notes", valid_form.merge("title" => "")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("제목을 입력")
    end

    it "category가 enum 외면 422 + '유효하지 않은 카테고리'" do
      post "/notes", valid_form.merge("category" => "alien")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("유효하지 않은 카테고리")
    end

    it "source가 비면 422 + '출처를 입력해 주세요'" do
      post "/notes", valid_form.merge("source" => "")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("출처를 입력")
    end

    it "실패 시 입력값을 폼에 다시 채워 넣는다" do
      post "/notes", valid_form.merge("body" => "")
      expect(last_response.body).to include('value="1단원 정리"')
      expect(last_response.body).to include('value="교과서 1단원"')
      expect(last_response.body).to include("selected") # category=lessons 유지
    end

    it "실패 시 인덱스·파일은 만들지 않는다" do
      post "/notes", valid_form.merge("title" => "")
      expect(db[:entries].count).to eq(0)
      expect(vault_dir.join("20_Notes").exist?).to be false
    end
  end

  describe "GET /notes (목록 + 카테고리 필터)" do
    before do
      post "/notes", valid_form.merge("title" => "수업1", "category" => "lessons")
      post "/notes", valid_form.merge("title" => "수업2", "category" => "lessons")
      post "/notes", valid_form.merge("title" => "연수1", "category" => "trainings")
    end

    it "전체에서 3건이 보인다" do
      get "/notes"
      expect(last_response.body).to include("총 3건")
      expect(last_response.body.scan('class="note-card"').size).to eq(3)
    end

    it "?category=lessons 로 필터링하면 lessons 2건만 보인다" do
      get "/notes?category=lessons"
      expect(last_response.body).to include("총 2건")
      expect(last_response.body).to include("수업1")
      expect(last_response.body).to include("수업2")
      expect(last_response.body).not_to include("연수1")
    end

    it "?category=trainings 면 trainings 1건" do
      get "/notes?category=trainings"
      expect(last_response.body).to include("총 1건")
      expect(last_response.body).to include("연수1")
    end

    it "잘못된 category 파라미터는 무시되고 전체 표시" do
      get "/notes?category=alien"
      expect(last_response.body).to include("총 3건")
    end
  end

  describe "내비게이션" do
    # 글쓰기 메뉴 정비 (2026-05-12) — 필기 진입점이 메뉴에서 제거됨.
    # /notes 라우트 자체는 호환용으로 살아있음 (북마크·외부 링크).
    it "/notes 직접 접근 가능 (북마크 호환)" do
      get "/notes"
      expect(last_response.status).to eq(200)
    end
  end
end
