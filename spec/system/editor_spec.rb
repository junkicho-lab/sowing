# frozen_string_literal: true

require "rack/test"

RSpec.describe "CodeMirror 마크다운 에디터 통합 (W2-T06)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before { header "Host", "127.0.0.1" }

  describe "Importmap + Stimulus 등록" do
    before { get "/" }

    it "importmap에 codemirror·lang-markdown URL이 포함된다" do
      expect(last_response.body).to include('"codemirror": "https://esm.sh/codemirror')
      expect(last_response.body).to include('"@codemirror/lang-markdown"')
      expect(last_response.body).to include('"controllers/editor": "/js/controllers/editor_controller.js"')
    end

    it "Stimulus에 'editor' 컨트롤러를 register한다" do
      expect(last_response.body).to include('stimulus.register("editor", EditorController)')
    end

    it "JS 파일이 정적 자원으로 제공된다" do
      get "/js/controllers/editor_controller.js"
      expect(last_response).to be_ok
      expect(last_response.body).to include("export default class extends Controller")
      expect(last_response.body).to include('from "codemirror"')
      expect(last_response.body).to include('from "@codemirror/lang-markdown"')
    end
  end

  describe "필기 폼 (GET /notes/new)" do
    before { get "/notes/new" }

    it "본문 영역이 editor partial로 감싸진다" do
      expect(last_response.body).to include('data-controller="editor"')
      expect(last_response.body).to include('data-editor-target="textarea"')
    end

    it "textarea name='body'와 id='note_body'가 유지된다 (서버 검증·라벨 호환)" do
      expect(last_response.body).to include('id="note_body"')
      expect(last_response.body).to include('name="body"')
    end

    it "초기 polish: required 속성은 textarea에 그대로 (JS가 connect에서 제거)" do
      expect(last_response.body).to match(/<textarea[^>]*required[^>]*data-editor-target="textarea"|<textarea[^>]*data-editor-target="textarea"[^>]*required/)
    end
  end

  describe "기록 폼 (GET /records/new)" do
    before { get "/records/new" }

    it "본문 영역이 editor partial로 감싸진다" do
      expect(last_response.body).to include('data-controller="editor"')
      expect(last_response.body).to include('data-editor-target="textarea"')
      expect(last_response.body).to include('id="record_body"')
    end
  end

  describe "필기 편집 폼 (prefill)" do
    let(:db) { Sowing::Core::DB.connection }
    let(:vault_dir) { Sowing::Core::Paths.vault_dir }

    before do
      db[:entry_tags].delete
      db[:tags].delete
      db[:entries].delete
      require "fileutils"
      FileUtils.rm_rf(vault_dir.join("20_Notes"))

      post "/notes", {
        "title" => "원본",
        "body" => "기존 본문 내용\n\n두 번째 줄",
        "category" => "lessons",
        "source" => "교과서"
      }
      @id = db[:entries].first[:id]
    end

    it "edit 폼의 textarea에 기존 본문이 들어간다 (CodeMirror가 이를 초기 doc으로 사용)" do
      get "/notes/#{@id}/edit"
      expect(last_response).to be_ok
      expect(last_response.body).to include("기존 본문 내용")
      expect(last_response.body).to include('data-editor-target="textarea"')
    end
  end

  describe "메모 모달은 영향 없음" do
    before { get "/" }

    it "빠른 메모 모달의 textarea는 일반 textarea (data-editor-target 없음)" do
      modal = last_response.body[/<dialog[^>]*id="quick_modal".*?<\/dialog>/m]
      expect(modal).to include('class="quick-modal__textarea"')
      expect(modal).not_to include("data-editor-target")
    end
  end

  describe "POST 동작 무영향" do
    let(:db) { Sowing::Core::DB.connection }
    let(:vault_dir) { Sowing::Core::Paths.vault_dir }

    before do
      db[:entry_tags].delete
      db[:tags].delete
      db[:entries].delete
      require "fileutils"
      FileUtils.rm_rf(vault_dir.join("20_Notes"))
      FileUtils.rm_rf(vault_dir.join("30_Records"))
    end

    it "JS 비활성에서도 plain textarea POST가 정상 처리된다 (progressive enhancement)" do
      post "/notes", {
        "title" => "제목",
        "body" => "본문",
        "category" => "lessons",
        "source" => "출처"
      }
      expect(last_response.status).to be_between(300, 399)
      expect(db[:entries].count).to eq(1)
    end
  end
end
