# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "기록 라우트", type: :request do
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
    FileUtils.rm_rf(vault_dir.join("30_Records"))
    FileUtils.rm_rf(vault_dir.join(".sowing"))
  end

  def valid_form(**overrides)
    {
      "title" => "5월 학급운영 회고",
      "body" => "이번 달 돌아보기.",
      "category" => "학급운영",
      "promoted_from" => "",
      "tags" => "회고"
    }.merge(overrides.transform_keys(&:to_s))
  end

  def post_create(**overrides)
    post "/records", valid_form(**overrides)
    db[:entries].where(mode: "record").first[:id]
  end

  describe "GET /records (빈 상태)" do
    before { get "/records" }

    it "200 OK + 첫 기록 작성 CTA" do
      expect(last_response).to be_ok
      expect(last_response.body).to include("총 0건")
      expect(last_response.body).to include("+ 첫 기록 작성하기")
    end

    it "사용된 카테고리가 없으니 필터 탭이 없다" do
      expect(last_response.body).not_to include("filter-tabs")
    end
  end

  describe "GET /records/new" do
    before { get "/records/new" }

    it "폼에 5개 필드 (title, category, body, promoted_from, tags)" do
      expect(last_response).to be_ok
      %w[record_title record_category record_body record_promoted_from record_tags].each do |id|
        expect(last_response.body).to include(%(id="#{id}"))
      end
    end

    it "category는 자유 텍스트 input + datalist" do
      expect(last_response.body).to include('list="record_categories_datalist"')
      expect(last_response.body).to include("<datalist")
    end
  end

  describe "POST /records (정상)" do
    it "/records/:id로 redirect한다" do
      post "/records", valid_form
      expect(last_response.status).to be_between(300, 399)
      id = db[:entries].first[:id]
      expect(last_response.headers["location"]).to end_with("/records/#{id}")
    end

    it "30_Records/{YYYY}/{category}/{title}.md 생성" do
      post "/records", valid_form
      year = Time.now.year
      expect(vault_dir.join("30_Records/#{year}/학급운영/5월 학급운영 회고.md")).to exist
    end

    it "promoted_from 빈 문자열은 nil로 처리 (인덱스 NULL)" do
      post "/records", valid_form(promoted_from: "")
      expect(db[:entries].first[:promoted_from]).to be_nil
    end

    it "promoted_from 입력하면 인덱스에 기록" do
      post "/records", valid_form(promoted_from: "00_Inbox/y.md")
      expect(db[:entries].first[:promoted_from]).to eq("00_Inbox/y.md")
    end
  end

  describe "POST /records (검증 실패)" do
    it "title 비면 422" do
      post "/records", valid_form(title: "")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("제목을 입력")
    end

    it "category 비면 422" do
      post "/records", valid_form(category: "")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("카테고리를 입력")
    end

    it "실패 시 폼에 입력값 에코 + 인덱스 변경 없음" do
      post "/records", valid_form(title: "", body: "에코할 본문")
      expect(last_response.body).to include("에코할 본문")
      expect(db[:entries].count).to eq(0)
    end
  end

  describe "GET /records/:id (show)" do
    let!(:id) { post_create }

    it "마크다운 렌더링 + 메타 + 편집 버튼" do
      get "/records/#{id}"
      expect(last_response).to be_ok
      expect(last_response.body).to include("5월 학급운영 회고")
      expect(last_response.body).to include("학급운영")
      expect(last_response.body).to include("href=\"/records/#{id}/edit\"")
    end

    it "없는 id는 404" do
      get "/records/01XXXXXXXXXXXXXXXXXXXXXXXX"
      expect(last_response.status).to eq(404)
    end

    it "Note id로 접근하면 mode mismatch → 404" do
      Sowing::UseCases::CreateNote.new(
        vault_repo: Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir),
        index_repo: Sowing::Repositories::IndexRepo.new
      ).call(title: "n", body: "b", category: "lessons", source: "s")
      note_id = db[:entries].where(mode: "note").first[:id]
      get "/records/#{note_id}"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /records/:id/edit + PATCH" do
    let!(:id) { post_create }

    it "GET edit는 폼을 prefill하고 _method=patch가 들어간다" do
      get "/records/#{id}/edit"
      expect(last_response).to be_ok
      expect(last_response.body).to include('value="5월 학급운영 회고"')
      expect(last_response.body).to include('value="학급운영"')
      expect(last_response.body).to include('name="_method" value="patch"')
    end

    it "PATCH로 카테고리 변경 시 새 디렉토리에 쓰고 옛 위치는 휴지통" do
      patch "/records/#{id}", valid_form(category: "수업철학")
      year = Time.now.year
      expect(vault_dir.join("30_Records/#{year}/수업철학/5월 학급운영 회고.md")).to exist
      expect(vault_dir.join("30_Records/#{year}/학급운영/5월 학급운영 회고.md")).not_to exist
      expect(vault_dir.join(".sowing/trash/30_Records/#{year}/학급운영/5월 학급운영 회고.md")).to exist
    end

    it "PATCH 실패 시 422 + 폼" do
      patch "/records/#{id}", valid_form(title: "")
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("제목을 입력")
    end

    it "PATCH 정상 후 /records/:id로 redirect" do
      patch "/records/#{id}", valid_form(body: "수정된 본문")
      expect(last_response.status).to be_between(300, 399)
      expect(last_response.headers["location"]).to end_with("/records/#{id}")
    end
  end

  describe "카테고리 필터 + datalist" do
    before do
      post "/records", valid_form(title: "A", category: "학급운영")
      post "/records", valid_form(title: "B", category: "수업철학")
      post "/records", valid_form(title: "C", category: "수업철학")
    end

    it "?category=학급운영 → 1건" do
      get "/records", category: "학급운영"
      expect(last_response.body).to include("총 1건")
    end

    it "?category=수업철학 → 2건" do
      get "/records", category: "수업철학"
      expect(last_response.body).to include("총 2건")
    end

    it "잘못된 category는 무시되고 전체" do
      get "/records", category: "없는것"
      expect(last_response.body).to include("총 3건")
    end

    it "filter-tabs에 distinct 카테고리들이 표시된다" do
      get "/records"
      expect(last_response.body).to include("filter-tabs")
      expect(last_response.body).to include(">학급운영<")
      expect(last_response.body).to include(">수업철학<")
    end

    it "new 폼의 datalist에 사용된 카테고리가 채워진다" do
      get "/records/new"
      expect(last_response.body).to include('<option value="학급운영">')
      expect(last_response.body).to include('<option value="수업철학">')
    end
  end

  describe "내비게이션" do
    it "헤더의 '기록' 링크가 활성화" do
      get "/"
      expect(last_response.body).to include('<a href="/records">기록</a>')
    end
  end
end
