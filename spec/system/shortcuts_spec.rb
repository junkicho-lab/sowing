# frozen_string_literal: true

require "rack/test"

# Phase 14 W30 PoC — 단축키 사용자 정의.
RSpec.describe "단축키 사용자 정의 (Phase 14 W30 PoC)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    Sowing::Core::Settings.reset!
    Sowing::Core::Settings.save(
      "onboarding_completed" => true,
      "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00"
    )
  end

  after { Sowing::Core::Settings.reset! }

  describe "Settings DEFAULTS" do
    it "shortcut_quick_memo 기본 'm'" do
      Sowing::Core::Settings.reset!
      expect(Sowing::Core::Settings.load["shortcut_quick_memo"]).to eq("m")
    end

    it "shortcut_quick_search 기본 'k'" do
      Sowing::Core::Settings.reset!
      expect(Sowing::Core::Settings.load["shortcut_quick_search"]).to eq("k")
    end
  end

  describe "POST /settings/shortcuts — sanitize" do
    it "유효 영문 1글자 → 저장" do
      post "/settings/shortcuts",
        shortcut_quick_memo: "J",
        shortcut_quick_search: "P"
      expect(last_response.status).to eq(302)
      settings = Sowing::Core::Settings.load
      expect(settings["shortcut_quick_memo"]).to eq("j")
      expect(settings["shortcut_quick_search"]).to eq("p")
    end

    it "여러 글자 입력 → default 폴백" do
      post "/settings/shortcuts", shortcut_quick_memo: "abc", shortcut_quick_search: ""
      settings = Sowing::Core::Settings.load
      expect(settings["shortcut_quick_memo"]).to eq("m")
      expect(settings["shortcut_quick_search"]).to eq("k")
    end

    it "특수문자·숫자·다국어 → default" do
      post "/settings/shortcuts", shortcut_quick_memo: "1", shortcut_quick_search: "ㅁ"
      settings = Sowing::Core::Settings.load
      expect(settings["shortcut_quick_memo"]).to eq("m")
      expect(settings["shortcut_quick_search"]).to eq("k")
    end

    it "flash 안내에 새 매핑 표시" do
      post "/settings/shortcuts", shortcut_quick_memo: "j", shortcut_quick_search: "p"
      follow_redirect!
      expect(last_response.body).to include("⌘⇧J")
      expect(last_response.body).to include("⌘P")
    end
  end

  describe "Layout — window.SOWING_SHORTCUTS 주입" do
    it "default 값 (m, k) JSON 으로 노출" do
      get "/"
      expect(last_response.body).to match(/window\.SOWING_SHORTCUTS\s*=\s*\{[^}]*"quick_memo":\s*"m"/)
      expect(last_response.body).to match(/"quick_search":\s*"k"/)
    end

    it "사용자 변경 시 layout 에 반영" do
      Sowing::Core::Settings.update(
        shortcut_quick_memo: "j",
        shortcut_quick_search: "p"
      )
      get "/"
      expect(last_response.body).to include('"quick_memo":"j"')
      expect(last_response.body).to include('"quick_search":"p"')
    end

    it "Settings 손상 시 default 폴백" do
      allow(Sowing::Core::Settings).to receive(:load).and_raise(StandardError)
      expect { get "/" }.not_to raise_error
    end
  end

  describe "Settings UI" do
    it "settings 페이지에 두 단축키 input + modifier prefix" do
      get "/settings"
      expect(last_response.body).to include("⌘⇧")  # 빠른 메모 prefix
      expect(last_response.body).to include('name="shortcut_quick_memo"')
      expect(last_response.body).to include('name="shortcut_quick_search"')
    end

    it "현재 값이 input 의 value 에 (대문자 표시)" do
      Sowing::Core::Settings.update(shortcut_quick_memo: "j")
      get "/settings"
      expect(last_response.body).to match(/<input[^>]*name="shortcut_quick_memo"[^>]*value="J"/)
    end

    it "pattern 검증 — [a-zA-Z]" do
      get "/settings"
      expect(last_response.body).to match(/<input[^>]*name="shortcut_quick_memo"[^>]*pattern="\[a-zA-Z\]"/)
    end
  end

  describe "JS controller — 사용자 정의 키 사용" do
    let(:memo_js) { File.read(File.join(Sowing.root, "public/js/controllers/quick_memo_controller.js")) }
    let(:search_js) { File.read(File.join(Sowing.root, "public/js/controllers/quick_search_controller.js")) }

    it "quick_memo 가 window.SOWING_SHORTCUTS.quick_memo 참조" do
      expect(memo_js).to include("window.SOWING_SHORTCUTS")
      expect(memo_js).to include("quick_memo")
    end

    it "quick_search 가 window.SOWING_SHORTCUTS.quick_search 참조" do
      expect(search_js).to include("window.SOWING_SHORTCUTS")
      expect(search_js).to include("quick_search")
    end

    it "default 폴백 — window 변수 없어도 작동 (??:'m'/'k')" do
      expect(memo_js).to include('|| "m"')
      expect(search_js).to include('|| "k"')
    end
  end
end
