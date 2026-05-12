# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "마크다운 라이브 프리뷰 (W2-T07)", type: :request do
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
    FileUtils.rm_rf(vault_dir.join("30_Records"))
  end

  describe "POST /preview" do
    it "200 OK + Turbo Stream content-type" do
      post "/preview", body: "# 제목"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("text/vnd.turbo-stream.html")
    end

    it "preview_pane을 update하는 turbo-stream을 반환한다" do
      post "/preview", body: "# 제목\n\n본문 내용"
      expect(last_response.body).to include('<turbo-stream action="update" target="preview_pane">')
      expect(last_response.body).to include("<h1>제목</h1>")
      expect(last_response.body).to include("<p>본문 내용</p>")
    end

    it "GFM 확장(테이블, tasklist, autolink)을 렌더한다" do
      md = "- [x] 완료\n- [ ] 미완\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
      post "/preview", body: md
      expect(last_response.body).to include('type="checkbox" checked="" disabled=""')
      expect(last_response.body).to include("<table>")
    end

    it "raw <script>는 차단된다 (XSS)" do
      post "/preview", body: "<script>alert('xss')</script>"
      expect(last_response.body).not_to include("<script>alert('xss')</script>")
    end

    it "빈 본문은 빈 응답을 보낸다" do
      post "/preview", body: ""
      expect(last_response).to be_ok
      # turbo-stream의 template은 비어 있음
      expect(last_response.body).to match(/<template>\s*<\/template>/)
    end

    it "응답 시간이 합리적으로 빠르다 (<200ms, ROADMAP '300ms 이내' 충족)" do
      md = "# 제목\n\n" + ("본문 한 줄. " * 50) + "\n"
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      post "/preview", body: md
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      expect(elapsed_ms).to be < 200, "POST /preview took #{elapsed_ms.round(1)}ms"
    end
  end

  describe "필기 폼 (GET /notes/new) 의 split 레이아웃" do
    before { get "/notes/new" }

    it "에디터·프리뷰 분할 컨테이너가 있다" do
      expect(last_response.body).to include('class="editor-with-preview"')
      expect(last_response.body).to include('data-controller="preview"')
    end

    it "preview controller에 url·debounce 값이 설정된다" do
      expect(last_response.body).to include('data-preview-url-value="/preview"')
      expect(last_response.body).to include('data-preview-debounce-ms-value="300"')
    end

    it "#preview_pane이 비어 있다 (신규 폼)" do
      expect(last_response.body).to match(/<div id="preview_pane"[^>]*class="preview-pane prose">\s*<\/div>/)
    end

    it "Stimulus에 'preview' 컨트롤러가 register된다" do
      expect(last_response.body).to include('stimulus.register("preview", PreviewController)')
    end

    it "에디터 partial은 그대로 nested" do
      expect(last_response.body).to include('data-controller="editor"')
      expect(last_response.body).to include('data-editor-target="textarea"')
    end
  end

  describe "필기 편집 폼의 초기 프리뷰 (서버측 commonmarker)" do
    let!(:id) {
      post "/notes", {
        "title" => "원본",
        "body" => "# 핵심\n\n본문 내용",
        "category" => "lessons",
        "source" => "교과서"
      }
      db[:entries].first[:id]
    }

    it "edit 진입 시 #preview_pane에 이미 렌더된 HTML이 들어 있다 (JS 없이도 보임)" do
      get "/notes/#{id}/edit"
      preview_section = last_response.body[/<div id="preview_pane"[^>]*>(.*?)<\/div>/m, 1]
      expect(preview_section).to include("<h1>핵심</h1>")
      expect(preview_section).to include("<p>본문 내용</p>")
    end
  end

  describe "기록 폼" do
    it "GET /records/new 도 동일한 split + #preview_pane" do
      get "/records/new"
      expect(last_response.body).to include('class="editor-with-preview"')
      expect(last_response.body).to include('id="preview_pane"')
    end
  end

  describe "JS 컨트롤러 정적 자원" do
    it "/js/controllers/preview_controller.js 가 서빙되고 디바운스 로직이 들어 있다" do
      get "/js/controllers/preview_controller.js"
      expect(last_response).to be_ok
      expect(last_response.body).to include("editor:input")
      expect(last_response.body).to include("renderStreamMessage")
      expect(last_response.body).to include("debounceMs")
    end

    it "editor_controller가 doc 변경 시 'editor:input' 이벤트를 dispatch한다" do
      get "/js/controllers/editor_controller.js"
      expect(last_response.body).to include('CustomEvent("editor:input"')
      expect(last_response.body).to include("bubbles: true")
    end
  end

  describe "메모 모달은 영향 없음" do
    before { get "/" }

    it "메모 모달은 split 레이아웃을 사용하지 않는다 (단순 textarea)" do
      modal = last_response.body[/<dialog[^>]*id="quick_modal".*?<\/dialog>/m]
      expect(modal).not_to include("editor-with-preview")
      expect(modal).not_to include("preview_pane")
    end
  end
end
