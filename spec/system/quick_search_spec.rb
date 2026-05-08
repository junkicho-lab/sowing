# frozen_string_literal: true

require "rack/test"
require "fileutils"
require "json"

RSpec.describe "Cmd+K 빠른 검색 (W4-T04)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }

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
    FileUtils.rm_rf(vault_dir.join("00_Inbox"))
    FileUtils.rm_rf(vault_dir.join("20_Notes"))
    FileUtils.rm_rf(vault_dir.join("30_Records"))
  end

  def parsed
    JSON.parse(last_response.body, symbolize_names: true)
  end

  describe "GET /api/quick_search 응답 형식" do
    before do
      post "/notes",
        "title" => "협동학습 정리",
        "body" => "본문",
        "category" => "lessons",
        "source" => "교과서"
      get "/api/quick_search", q: "협동학습"
    end

    it "200 OK + application/json" do
      expect(last_response).to be_ok
      expect(last_response.headers["content-type"]).to include("application/json")
    end

    it "{ results: [...] } 구조" do
      expect(parsed).to have_key(:results)
      expect(parsed[:results]).to be_an(Array)
      expect(parsed[:results].size).to eq(1)
    end

    it "각 항목은 path/title/mode/icon/url 5개 키" do
      item = parsed[:results].first
      expect(item.keys).to contain_exactly(:path, :title, :mode, :icon, :url)
    end

    it "note url은 /notes/:id" do
      item = parsed[:results].first
      note_id = db[:entries].where(mode: "note").first[:id]
      expect(item[:url]).to eq("/notes/#{note_id}")
    end
  end

  describe "url 매핑 — mode별" do
    before do
      post "/memos", body: "검색본문 메모1"
      post "/notes",
        "title" => "검색본문 필기",
        "body" => "본문",
        "category" => "lessons",
        "source" => "교과서"
      post "/records",
        "title" => "검색본문 기록",
        "body" => "본문",
        "category" => "학급운영"
    end

    it "note → /notes/:id, record → /records/:id, memo → /memos" do
      get "/api/quick_search", q: "검색본문"
      results = parsed[:results]

      url_by_mode = results.group_by { |r| r[:mode] }.transform_values { |arr| arr.first[:url] }

      note_id = db[:entries].where(mode: "note").first[:id]
      record_id = db[:entries].where(mode: "record").first[:id]

      expect(url_by_mode["note"]).to eq("/notes/#{note_id}")
      expect(url_by_mode["record"]).to eq("/records/#{record_id}")
      expect(url_by_mode["memo"]).to eq("/memos")
    end

    it "icon은 ADR-004 기준 (📖/📝/💭)" do
      get "/api/quick_search", q: "검색본문"
      icons = parsed[:results].group_by { |r| r[:mode] }
        .transform_values { |arr| arr.map { |r| r[:icon] }.uniq }
      expect(icons["record"]).to eq(["📖"])
      expect(icons["note"]).to eq(["📝"])
      expect(icons["memo"]).to eq(["💭"])
    end
  end

  describe "memo display title — (메모) 본문 첫 60자" do
    before { post "/memos", body: "이것은 충분히 긴 검색본문 메모입니다. " * 5 }

    it "memo title은 '(메모) {본문 첫 60자}' 형식" do
      get "/api/quick_search", q: "검색본문"
      memo_item = parsed[:results].find { |r| r[:mode] == "memo" }
      expect(memo_item[:title]).to start_with("(메모) ")
      excerpt = memo_item[:title].sub("(메모) ", "")
      expect(excerpt.length).to be <= 60
    end
  end

  describe "본문 검색 (W4-T02 search_with_filters 사용)" do
    before do
      post "/memos", body: "오늘 1교시 협동학습 활기"
      post "/notes",
        "title" => "다른 제목",
        "body" => "본문에 협동학습 키워드",
        "category" => "lessons",
        "source" => "교과서"
    end

    it "title뿐 아니라 본문도 검색" do
      get "/api/quick_search", q: "협동학습"
      expect(parsed[:results].size).to eq(2)
    end

    it "한국어 2글자도 LIKE 폴백으로 매칭" do
      get "/api/quick_search", q: "활기"
      expect(parsed[:results].size).to eq(1)
    end
  end

  describe "엣지 케이스" do
    it "q 빈 문자열 → 빈 배열" do
      get "/api/quick_search", q: ""
      expect(parsed[:results]).to eq([])
    end

    it "q 미지정 → 빈 배열" do
      get "/api/quick_search"
      expect(parsed[:results]).to eq([])
    end

    it "양 끝 공백 strip" do
      post "/notes",
        "title" => "회고",
        "body" => "본문",
        "category" => "lessons",
        "source" => "교과서"
      get "/api/quick_search", q: "  회고  "
      expect(parsed[:results].size).to eq(1)
    end

    it "매칭 없으면 빈 배열" do
      get "/api/quick_search", q: "절대없는키워드xyz"
      expect(parsed[:results]).to eq([])
    end
  end

  describe "limit (최대 25건)" do
    it "30건 매칭 시 25건만 반환" do
      30.times { |i| post "/memos", body: "검색본문가능 #{i}" }
      get "/api/quick_search", q: "검색본문가능"
      expect(parsed[:results].size).to eq(25)
    end
  end

  describe "레이아웃 통합" do
    it "모든 페이지 layout에 quick-search 모달이 포함됨" do
      get "/"
      expect(last_response.body).to include('id="quick_search_modal"')
      expect(last_response.body).to include('data-controller="quick-search"')
      expect(last_response.body).to include('data-quick-search-target="input"')
      expect(last_response.body).to include('data-quick-search-target="results"')
    end

    it "Stimulus controller가 importmap + register에 등록됨" do
      get "/"
      expect(last_response.body).to include("controllers/quick_search")
      expect(last_response.body).to include('stimulus.register("quick-search"')
    end

    it "controller JS 파일이 서빙됨" do
      get "/js/controllers/quick_search_controller.js"
      expect(last_response).to be_ok
      expect(last_response.body).to include("quick-search")
      expect(last_response.body).to include("Cmd/Ctrl+K")
    end
  end
end
