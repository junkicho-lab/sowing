# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "메모 생성 라우트", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Infrastructure::DB.connection }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    # 기본 vault_dir 자리를 깨끗이 — 테스트 간 누적 방지
    vault = Sowing::Infrastructure::Paths.vault_dir
    FileUtils.rm_rf(vault.join("00_Inbox"))
  end

  describe "POST /memos" do
    context "정상 본문" do
      before { post "/memos", body: "오늘 1교시 수업이 활기찼다" }

      it "200 OK + Turbo Stream content-type을 반환한다" do
        expect(last_response.status).to eq(200)
        expect(last_response.headers["content-type"]).to include("text/vnd.turbo-stream.html")
      end

      it "recent_memos_list에 prepend하는 turbo-stream을 보낸다" do
        expect(last_response.body).to include('<turbo-stream action="prepend" target="recent_memos_list">')
        expect(last_response.body).to include("memo-card")
        expect(last_response.body).to include("오늘 1교시 수업이 활기찼다")
      end

      it "오류 영역(quick_modal_error)을 비우는 turbo-stream도 함께 보낸다" do
        expect(last_response.body).to include('target="quick_modal_error"')
      end

      it "SQLite 인덱스에 row가 추가된다" do
        expect(db[:entries].count).to eq(1)
      end
    end

    context "빈 본문" do
      before { post "/memos", body: "" }

      it "422 Unprocessable Entity를 반환한다" do
        expect(last_response.status).to eq(422)
      end

      it "오류 메시지를 quick_modal_error에 update하는 turbo-stream을 보낸다" do
        expect(last_response.body).to include('<turbo-stream action="update" target="quick_modal_error">')
        expect(last_response.body).to include("본문을 입력")
      end

      it "인덱스에 row를 추가하지 않는다" do
        expect(db[:entries].count).to eq(0)
      end
    end

    context "공백만 있는 본문" do
      it "422를 반환한다" do
        post "/memos", body: "   \n\t  "
        expect(last_response.status).to eq(422)
      end
    end
  end

  describe "GET / 의 빠른 메모 모달" do
    before { get "/" }

    it "<dialog id=\"quick_modal\"> 가 layout에 포함되어 있다" do
      expect(last_response.body).to include('<dialog id="quick_modal"')
      expect(last_response.body).to include('data-controller="quick-memo"')
    end

    it "form은 /memos에 POST 한다" do
      expect(last_response.body).to include('action="/memos"')
      expect(last_response.body).to include('method="post"')
    end

    it "Turbo 제출 후 Stimulus가 모달을 닫도록 data-action이 걸려 있다" do
      expect(last_response.body).to include("turbo:submit-end->quick-memo#onSubmitEnd")
    end

    it "textarea에 Cmd/Ctrl+Enter 핸들러가 걸려 있다" do
      expect(last_response.body).to include("keydown->quick-memo#onTextareaKeydown")
    end

    it "Stimulus quick_memo 컨트롤러를 importmap으로 로드한다" do
      expect(last_response.body).to include('"controllers/quick_memo": "/js/controllers/quick_memo_controller.js"')
      expect(last_response.body).to include('stimulus.register("quick-memo", QuickMemoController)')
    end

    it "JS 파일이 정적 자원으로 제공된다" do
      get "/js/controllers/quick_memo_controller.js"
      expect(last_response).to be_ok
      expect(last_response.body).to include("export default class extends Controller")
      expect(last_response.body).to include("metaKey || event.ctrlKey")
    end
  end

  describe "GET / 의 최근 메모 표시" do
    before do
      post "/memos", body: "첫 메모"
      get "/"
    end

    it "recent_memos_list 안에 방금 만든 메모가 보인다" do
      expect(last_response.body).to include('id="recent_memos_list"')
      expect(last_response.body).to include("첫 메모")
    end
  end
end
