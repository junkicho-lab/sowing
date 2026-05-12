# frozen_string_literal: true

require "rack/test"

# 실제 인터랙션(Tab/Enter로 선택, 디바운스 후 팝업)은 Capybara+headless 브라우저
# 도입 후 검증 가능. 본 spec은 통합 표면 — JS 정적 자원·importmap·API 응답 형식이
# CodeMirror autocomplete 익스텐션이 기대하는 모양인지 검증.

RSpec.describe "위키링크 자동완성 통합 (W3-T04)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before { header "Host", "127.0.0.1" }

  describe "Importmap" do
    before { get "/" }

    it "@codemirror/autocomplete가 importmap에 포함된다" do
      expect(last_response.body).to include('"@codemirror/autocomplete": "https://esm.sh/@codemirror/autocomplete')
    end
  end

  describe "editor_controller.js" do
    before { get "/js/controllers/editor_controller.js" }

    it "정적 자원으로 서빙된다" do
      expect(last_response).to be_ok
    end

    it "@codemirror/autocomplete 모듈을 import한다" do
      expect(last_response.body).to include('import { autocompletion } from "@codemirror/autocomplete"')
    end

    it "[[ 패턴을 매칭하는 wikiLinkSource 함수가 존재한다" do
      expect(last_response.body).to include("wikiLinkSource")
      expect(last_response.body).to include("/\\[\\[([^\\]|\\n]*)$/")
    end

    it "/api/wiki_complete 엔드포인트를 호출한다" do
      expect(last_response.body).to include("/api/wiki_complete?q=")
      expect(last_response.body).to include("encodeURIComponent(query)")
    end

    it "200ms 디바운스로 autocompletion 익스텐션 활성화" do
      expect(last_response.body).to include("activateOnTypingDelay: 200")
    end

    it "응답 결과를 CodeMirror completion options 형식으로 매핑" do
      # API 결과의 title/mode/icon → label/type/detail
      expect(last_response.body).to include("label: r.title")
      expect(last_response.body).to include("type: r.mode")
      expect(last_response.body).to include("detail: r.icon")
      expect(last_response.body).to include("apply: `${r.title}]]`")
    end

    it "from은 [[ 다음 위치 (before.from + 2) — 사용자가 입력한 [[는 보존" do
      expect(last_response.body).to include("from: before.from + 2")
    end

    it "validFor 정규식으로 cursor 뒤 ]·|·\\n 입력 시 query 무효화" do
      expect(last_response.body).to include("validFor: /^[^\\]|\\n]*$/")
    end
  end

  describe "API 응답이 CodeMirror autocomplete 형식 호환" do
    let(:db) { Sowing::Core::DB.connection }
    let(:vault_dir) { Sowing::Core::Paths.vault_dir }

    before do
      require "fileutils"
      db[:links].delete
      db[:entry_tags].delete
      db[:tags].delete
      db[:entries].delete
      FileUtils.rm_rf(vault_dir.join("20_Notes"))

      post "/notes", "title" => "회고 정리", "body" => "본문",
        "category" => "lessons", "source" => "교과서"
    end

    it "results 각 항목에 title/mode/icon이 모두 포함된다 (label/type/detail 매핑)" do
      get "/api/wiki_complete", q: "회고"
      result = JSON.parse(last_response.body, symbolize_names: true)[:results].first
      expect(result).to include(:title, :mode, :icon)
    end

    it "빈 q에 대해서도 200 OK + 결과 반환" do
      get "/api/wiki_complete", q: ""
      expect(last_response).to be_ok
      data = JSON.parse(last_response.body, symbolize_names: true)
      expect(data[:results]).not_to be_empty
    end
  end

  describe "CSS" do
    before { get "/css/application.css" }

    it "자동완성 tooltip 스타일이 정의됨" do
      expect(last_response.body).to include(".cm-tooltip-autocomplete")
      expect(last_response.body).to include("aria-selected")
    end

    it "completionDetail (icon 표시) 스타일이 디자인 토큰을 사용" do
      expect(last_response.body).to include(".cm-completionDetail")
    end
  end

  describe "기존 에디터 동작 무영향" do
    before { get "/notes/new" }

    it "에디터 partial이 그대로 렌더된다" do
      expect(last_response.body).to include('data-controller="editor"')
      expect(last_response.body).to include('data-editor-target="textarea"')
    end

    it "프리뷰 partial도 함께 렌더 (W2-T07 회귀)" do
      expect(last_response.body).to include('data-controller="preview"')
      expect(last_response.body).to include("preview_pane")
    end
  end
end
