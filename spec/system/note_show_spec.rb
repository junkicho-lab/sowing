# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "GET /notes/:id (필기 상세)", type: :request do
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
    FileUtils.rm_rf(vault_dir.join("00_Inbox"))
    FileUtils.rm_rf(vault_dir.join("20_Notes"))
  end

  def create_note(form = {})
    defaults = {
      "title" => "1단원 정리",
      "body" => "# 핵심\n\n오늘 배운 내용을 정리한다.\n\n- 항목 1\n- 항목 2\n",
      "category" => "lessons",
      "source" => "교과서 1단원",
      "tags" => "수업, 1학년"
    }
    post "/notes", defaults.merge(form)
    db[:entries].first[:id]
  end

  describe "정상 ID" do
    let!(:id) { create_note }
    before { get "/notes/#{id}" }

    it "200 OK + 제목·출처·카테고리 라벨이 보인다" do
      expect(last_response).to be_ok
      expect(last_response.body).to include("1단원 정리")
      expect(last_response.body).to include("교과서 1단원")
      expect(last_response.body).to include(">수업<") # 카테고리 라벨
    end

    it "마크다운 본문이 HTML로 렌더된다 (h1, ul)" do
      expect(last_response.body).to include("<h1>핵심</h1>")
      expect(last_response.body).to include("<li>항목 1</li>")
      expect(last_response.body).to include("<li>항목 2</li>")
    end

    it "헤더 앵커 링크가 없다 (옵시디언 호환 깔끔한 출력)" do
      expect(last_response.body).not_to include('class="anchor"')
      expect(last_response.body).not_to match(/<h1[^>]*><a[^>]*href="#/)
    end

    it "syntax highlighter 인라인 style이 없다 (우리 CSS로 통제)" do
      # 다크 테마 색상이 없어야 함
      expect(last_response.body).not_to include("#2b303b")
    end

    it "태그 목록을 보여준다" do
      expect(last_response.body).to include("#수업")
      expect(last_response.body).to include("#1학년")
    end

    it "목록으로 돌아가는 링크가 있다" do
      expect(last_response.body).to include('href="/notes"')
    end

    it "카테고리 라벨이 필터 링크로 동작한다" do
      expect(last_response.body).to include('href="/notes?category=lessons"')
    end

    it "페이지 제목에 노트 제목이 들어간다" do
      expect(last_response.body).to include("<title>1단원 정리 | Sowing</title>")
    end
  end

  describe "마크다운 안전성 (XSS)" do
    it "raw <script>는 렌더되지 않는다" do
      id = create_note(
        "title" => "안전 테스트",
        "body" => "<script>alert('xss')</script>\n\n본문"
      )
      get "/notes/#{id}"
      expect(last_response.body).not_to include("<script>alert('xss')</script>")
    end

    it "javascript: URL은 차단된다" do
      id = create_note(
        "title" => "안전 테스트",
        "body" => "[악성](javascript:alert(1))"
      )
      get "/notes/#{id}"
      expect(last_response.body).not_to include('href="javascript:')
    end
  end

  describe "위키링크 (W3-T01에서 처리, 현재는 plain text)" do
    it "[[다른 노트]] 는 그대로 텍스트로 출력된다" do
      id = create_note(body: "[[다른 노트]] 참고")
      get "/notes/#{id}"
      expect(last_response.body).to include("[[다른 노트]]")
      expect(last_response.body).not_to include('class="wikilink"')
    end
  end

  describe "404" do
    it "존재하지 않는 ID는 404" do
      get "/notes/01XXXXXXXXXXXXXXXXXXXXXXXX"
      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("필기를 찾을 수 없습니다")
    end

    it "임의 문자열 ID도 404 (Ulid 파싱 실패도 graceful)" do
      get "/notes/not-a-ulid"
      expect(last_response.status).to eq(404)
    end

    it "메모 ID로 접근하면 404 (mode mismatch)" do
      post "/memos", body: "메모 본문"
      memo_id = db[:entries].where(mode: "memo").first[:id]
      get "/notes/#{memo_id}"
      expect(last_response.status).to eq(404)
    end

    it "인덱스 row는 있지만 파일이 누락되면 404 (graceful)" do
      id = create_note
      indexed = Sowing::Repositories::IndexRepo.new.find(id)
      File.delete(vault_dir.join(indexed.path))
      get "/notes/#{id}"
      expect(last_response.status).to eq(404)
    end
  end

  describe "라우트 우선순위" do
    it "GET /notes/new 는 show 라우트에 의해 가로채지지 않는다" do
      get "/notes/new"
      expect(last_response).to be_ok
      expect(last_response.body).to include("필기 작성")
    end
  end
end
