# frozen_string_literal: true

require "rack/test"
require "fileutils"
require "json"

RSpec.describe "태그 시스템 (W3-T05)", type: :request do
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
    FileUtils.rm_rf(vault_dir.join("30_Records"))
  end

  describe "본문 #태그가 인덱싱된다 (frontmatter tags와 union)" do
    it "메모 본문의 #태그가 자동 추출되어 entry_tags에 삽입" do
      post "/memos", body: "오늘 #수업 1교시 활기. #1학년 학급."
      expect(db[:tags].select_map(:name)).to contain_exactly("수업", "1학년")
      memo_id = db[:entries].first[:id]
      expect(db[:entry_tags].where(entry_id: memo_id).count).to eq(2)
    end

    it "필기는 frontmatter tags + 본문 #태그를 union" do
      post "/notes",
        "title" => "정리",
        "body" => "본문 #추가",
        "category" => "lessons",
        "source" => "교과서",
        "tags" => "프론트, 또하나"

      expect(db[:tags].select_map(:name)).to contain_exactly("프론트", "또하나", "추가")
    end

    it "frontmatter와 본문에 같은 태그면 중복 저장 안 함 (정규화 union)" do
      post "/notes",
        "title" => "정리",
        "body" => "본문 #수업",
        "category" => "lessons",
        "source" => "교과서",
        "tags" => "수업"

      memo_id = db[:entries].first[:id]
      expect(db[:entry_tags].where(entry_id: memo_id).count).to eq(1)
    end
  end

  describe "GET /tags (태그 클라우드)" do
    it "사용된 태그가 없으면 안내 표시" do
      get "/tags"
      expect(last_response).to be_ok
      expect(last_response.body).to include("아직 사용된 태그가 없습니다")
    end

    it "태그를 사용 횟수 desc로 표시" do
      post "/memos", body: "#수업 #학급"
      post "/memos", body: "#수업"  # 수업이 2회 사용됨
      get "/tags"

      # tag-cloud 영역 안에서 수업이 학급보다 먼저 등장해야 함
      cloud = last_response.body[/<ul[^>]*tag-cloud[^>]*>.*?<\/ul>/m]
      idx_class = cloud.index("수업")
      idx_grade = cloud.index("학급")
      expect(idx_class).to be < idx_grade
      expect(last_response.body).to include("총 2개")
    end

    it "각 태그가 /tags/:name 링크를 가진다" do
      post "/memos", body: "#수업"
      get "/tags"
      # href 안의 한글은 보통 raw로 들어감 (브라우저가 자동 인코딩). 우리 view도 raw.
      expect(last_response.body).to include('href="/tags/수업"')
    end
  end

  describe "GET /tags/:name (태그별 entries)" do
    before do
      post "/memos", body: "메모 #수업"
      post "/notes",
        "title" => "필기 정리",
        "body" => "필기 본문 #수업",
        "category" => "lessons",
        "source" => "교과서"
    end

    it "해당 태그를 가진 모든 모드의 entries를 보여준다" do
      get "/tags/#{Rack::Utils.escape("수업")}"
      expect(last_response).to be_ok
      expect(last_response.body).to include("필기 정리") # note title
      expect(last_response.body).to include("총 2건")
    end

    it "각 entry는 모드 아이콘과 메타를 표시한다" do
      get "/tags/#{Rack::Utils.escape("수업")}"
      expect(last_response.body).to include("📝") # note icon
      expect(last_response.body).to include("💭") # memo icon
      expect(last_response.body).to include("필기")
      expect(last_response.body).to include("메모")
    end

    it "note는 /notes/:id로 링크" do
      get "/tags/#{Rack::Utils.escape("수업")}"
      note_id = db[:entries].where(mode: "note").first[:id]
      expect(last_response.body).to include("/notes/#{note_id}")
    end

    it "없는 태그는 빈 결과" do
      get "/tags/#{Rack::Utils.escape("없는태그")}"
      expect(last_response).to be_ok
      expect(last_response.body).to include("이 태그를 가진 항목이 없습니다")
    end

    it "← 모든 태그 링크 존재" do
      get "/tags/#{Rack::Utils.escape("수업")}"
      expect(last_response.body).to include("모든 태그")
      expect(last_response.body).to include('href="/tags"')
    end
  end

  describe "내비게이션" do
    it "헤더에 /tags 진입 링크 (Phase 13 IA — 쓴 글 보기 dropdown)" do
      get "/"
      expect(last_response.body).to include('href="/tags"')
    end
  end

  describe "GET /api/tag_complete (자동완성)" do
    before do
      post "/memos", body: "#수업 #수학 #영어"
    end

    it "JSON {tags: [...]} 형식 반환" do
      get "/api/tag_complete", q: ""
      data = JSON.parse(last_response.body, symbolize_names: true)
      expect(data).to have_key(:tags)
      expect(data[:tags]).to contain_exactly("수업", "수학", "영어")
    end

    it "q substring으로 필터링" do
      get "/api/tag_complete", q: "수"
      data = JSON.parse(last_response.body, symbolize_names: true)
      expect(data[:tags]).to contain_exactly("수업", "수학")
    end

    it "q 매칭 안 되면 빈 배열" do
      get "/api/tag_complete", q: "없는것"
      data = JSON.parse(last_response.body, symbolize_names: true)
      expect(data[:tags]).to eq([])
    end
  end

  describe "Editor 자동완성 통합 (W3-T05)" do
    it "editor_controller.js에 hashtagSource 함수가 존재한다" do
      get "/js/controllers/editor_controller.js"
      expect(last_response.body).to include("hashtagSource")
      expect(last_response.body).to include("/api/tag_complete?q=")
    end

    it "autocompletion override에 hashtagSource가 포함됨" do
      get "/js/controllers/editor_controller.js"
      expect(last_response.body).to include("override: [wikiLinkSource, hashtagSource]")
    end
  end
end
