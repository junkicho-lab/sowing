# frozen_string_literal: true

require "rack/test"

# Phase 14 W31 PoC — 모바일 햄버거 + 터치 chip 크기.
# JS 0 — checkbox + label + CSS :checked 패턴.
RSpec.describe "모바일 웹 UX 개선 (Phase 14 W31 PoC)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    Sowing::Infrastructure::Settings.save(
      "onboarding_completed" => true,
      "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00"
    )
  end

  after { Sowing::Infrastructure::Settings.reset! }

  describe "HTML — 햄버거 markup" do
    it "checkbox + label 패턴 노출 (JS 0)" do
      get "/"
      expect(last_response.body).to include('id="nav_mobile_toggle"')
      expect(last_response.body).to include('class="nav-mobile-toggle"')
      expect(last_response.body).to match(/<label for="nav_mobile_toggle"/)
    end

    it "햄버거·닫기 아이콘 둘 다 markup" do
      get "/"
      expect(last_response.body).to include("☰")
      expect(last_response.body).to include("✕")
    end

    it "햄버거 label 의 aria 속성" do
      get "/"
      # checkbox 에 aria-label, label 에 aria-hidden
      expect(last_response.body).to match(/<input[^>]*aria-label="메뉴 토글"/)
      expect(last_response.body).to match(/<label[^>]*aria-hidden="true"/)
    end

    it "햄버거 markup 이 nav 보다 앞에 (CSS sibling selector ~ 작동)" do
      get "/"
      toggle_idx = last_response.body.index('id="nav_mobile_toggle"')
      nav_idx = last_response.body.index('class="nav-v2 ')
      # nav-v2 가 첫 사용처
      nav_idx ||= last_response.body.index('nav-v2"')
      expect(toggle_idx).not_to be_nil
      expect(nav_idx).not_to be_nil
      expect(toggle_idx).to be < nav_idx
    end
  end

  describe "CSS — 모바일 햄버거 동작" do
    let(:css) { File.read(File.join(Sowing.root, "public/css/application.css")) }

    it "데스크톱에서 햄버거 버튼 display: none" do
      # 기본 (모바일 외) 에서 .nav-mobile-toggle__btn { display: none }
      expect(css).to match(/\.nav-mobile-toggle__btn \{[^}]*display:\s*none/m)
    end

    it "모바일 max-width 768px 에서 햄버거 inline-flex" do
      expect(css).to match(/@media \(max-width: 768px\)/)
      expect(css).to include(".nav-mobile-toggle__btn { display: inline-flex; }")
    end

    it ":checked + sibling 으로 nav 표시 (JS 0)" do
      expect(css).to include(".nav-mobile-toggle:checked ~ .nav-v2")
    end

    it "햄버거 버튼 ≥ 44px (Apple HIG)" do
      expect(css).to match(/\.nav-mobile-toggle__btn[^}]*min-width:\s*44px/m)
      expect(css).to match(/\.nav-mobile-toggle__btn[^}]*min-height:\s*44px/m)
    end
  end

  describe "CSS — 터치 chip 크기" do
    let(:css) { File.read(File.join(Sowing.root, "public/css/application.css")) }

    it "모바일에서 chip min-height ≥ 40px" do
      # quick-modal__chip / emotion-chip / view-recent__chip / plans__chip
      mobile_block = css[/@media \(max-width: 768px\) \{[^@]*(?:chip|emotion-chip)[^@]*\}/m]
      expect(mobile_block).to include("min-height: 40px")
    end

    it "emotion chip 모바일 min-width 64px (탭 영역 확보)" do
      expect(css).to match(/\.quick-modal__emotion-chip \{ min-width:\s*64px/)
    end

    it "Stats / view-recent / plans 아이템 모바일 패딩 보충" do
      expect(css).to match(/\.stats__card,[^{]*\.view-recent__item,[^{]*\.plans__item/m)
    end
  end

  describe "회귀 — 데스크톱 nav 영향 0" do
    it "GET / 응답 정상 + nav-v2 존재" do
      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("nav-v2")
      expect(last_response.body).to include("🖊 글쓰기")
    end

    it "Settings 페이지 정상" do
      get "/settings"
      expect(last_response.status).to eq(200)
    end
  end
end
