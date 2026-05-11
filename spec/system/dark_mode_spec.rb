# frozen_string_literal: true

require "rack/test"

# Phase 14 W29 PoC — 다크 모드.
RSpec.describe "다크 모드 (Phase 14 W29 PoC)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    Sowing::Infrastructure::Settings.reset!
    # Onboarding 완료 상태 — 일반 라우트 접근 위해
    Sowing::Infrastructure::Settings.save(
      "onboarding_completed" => true,
      "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00"
    )
  end

  after { Sowing::Infrastructure::Settings.reset! }

  describe "Settings — theme 옵션" do
    it "DEFAULTS 에 theme: 'auto'" do
      Sowing::Infrastructure::Settings.reset!
      expect(Sowing::Infrastructure::Settings.load["theme"]).to eq("auto")
    end

    it "POST /settings/theme — auto/light/dark allowlist 통과" do
      %w[auto light dark].each do |t|
        post "/settings/theme", theme: t
        expect(last_response.status).to eq(302)
        expect(Sowing::Infrastructure::Settings.load["theme"]).to eq(t)
      end
    end

    it "POST /settings/theme — 잘못된 값 → auto 폴백 (allowlist 보안)" do
      post "/settings/theme", theme: "evil-injection"
      expect(Sowing::Infrastructure::Settings.load["theme"]).to eq("auto")
    end

    it "flash 안내 표시 (테마별)" do
      post "/settings/theme", theme: "dark"
      follow_redirect!
      expect(last_response.body).to include("다크 모드")
    end
  end

  describe "Layout — html data-theme 동적" do
    it "theme=auto → data-theme 속성 없음 (CSS @media 결정)" do
      Sowing::Infrastructure::Settings.update(theme: "auto")
      get "/"
      expect(last_response.body).to match(/<html lang="ko">/)
      expect(last_response.body).not_to match(/<html[^>]*data-theme/)
    end

    it "theme=dark → <html data-theme=\"dark\">" do
      Sowing::Infrastructure::Settings.update(theme: "dark")
      get "/"
      expect(last_response.body).to include('data-theme="dark"')
    end

    it "theme=light → <html data-theme=\"light\">" do
      Sowing::Infrastructure::Settings.update(theme: "light")
      get "/"
      expect(last_response.body).to include('data-theme="light"')
    end

    it "color-scheme 메타 — auto → 'light dark', 그 외 → 명시" do
      Sowing::Infrastructure::Settings.update(theme: "auto")
      get "/"
      expect(last_response.body).to include('content="light dark"')

      Sowing::Infrastructure::Settings.update(theme: "dark")
      get "/"
      expect(last_response.body).to include('content="dark"')
    end

    it "Settings 손상 시 auto 폴백 (graceful)" do
      allow(Sowing::Infrastructure::Settings).to receive(:load).and_raise(StandardError, "boom")
      # 페이지가 raise 안 함 — layout rescue 가 auto 적용
      expect { get "/settings" }.not_to raise_error
    end
  end

  describe "Settings UI — 라디오 3종" do
    it "3 옵션 라디오 표시" do
      get "/settings"
      expect(last_response.body).to include('value="auto"')
      expect(last_response.body).to include('value="light"')
      expect(last_response.body).to include('value="dark"')
    end

    it "현재 theme = checked" do
      Sowing::Infrastructure::Settings.update(theme: "dark")
      get "/settings"
      # value="dark" 라디오에 checked
      expect(last_response.body).to match(/<input[^>]*value="dark"[^>]*checked/)
    end

    it "라벨 — 시스템 자동 · 라이트 · 다크" do
      get "/settings"
      expect(last_response.body).to include("🌗 시스템 자동")
      expect(last_response.body).to include("☀ 라이트")
      expect(last_response.body).to include("🌑 다크")
    end
  end

  describe "CSS — 다크 모드 토큰" do
    let(:css) { File.read(File.join(Sowing.root, "public/css/application.css")) }

    it ":root[data-theme=\"dark\"] override 정의" do
      expect(css).to include('[data-theme="dark"]')
      expect(css).to match(/data-theme="dark"\][^}]*--color-bg:/m)
    end

    it "@media prefers-color-scheme: dark 자동 따라감" do
      expect(css).to include("prefers-color-scheme: dark")
    end

    it "사용자 강제 light 모드 우선 (auto 무시)" do
      expect(css).to include(':root:not([data-theme="light"])')
    end

    it "hard-coded white 제거 — var(--color-card-bg) 토큰화" do
      # background: white 가 0이어야 (모두 토큰으로 교체)
      whites = css.scan(/^\s*background:\s*white\s*;/m).size
      expect(whites).to eq(0)
    end
  end
end
