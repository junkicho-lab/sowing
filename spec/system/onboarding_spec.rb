# frozen_string_literal: true

require "rack/test"

RSpec.describe "온보딩 마법사 (W7-T01)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    Sowing::Infrastructure::Settings.reset!
  end

  after do
    Sowing::Infrastructure::Settings.reset!
  end

  describe "redirect 동작" do
    it "온보딩 미완료 상태에서 /, /memos 등 진입 시 /onboarding/welcome 으로 redirect" do
      get "/"
      follow_redirect!
      expect(last_request.path).to eq("/onboarding/welcome")
    end

    it "온보딩 완료 후에는 redirect 없음 (/ 정상 200)" do
      Sowing::Infrastructure::Settings.update(onboarding_completed: true)
      get "/"
      expect(last_response.status).to eq(200)
    end

    it "/health, /css, /js는 온보딩 미완료여도 통과" do
      get "/health"
      expect(last_response.status).to eq(200)
      get "/css/application.css"
      expect(last_response.status).to eq(200)
    end
  end

  describe "단계 1: welcome" do
    it "GET /onboarding/welcome — Sowing 소개 + 시작하기 링크" do
      get "/onboarding/welcome"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("환영합니다")
      expect(last_response.body).to include("/onboarding/vault")
    end
  end

  describe "단계 2: vault" do
    it "GET /onboarding/vault — 현재 볼트 경로 표시" do
      get "/onboarding/vault"
      expect(last_response.body).to include(Sowing::Infrastructure::Paths.vault_dir.to_s)
    end

    it "POST /onboarding/vault — vault_consent 저장 + profile로 redirect" do
      post "/onboarding/vault"
      expect(last_response.status).to eq(302)
      expect(last_response["Location"]).to end_with("/onboarding/profile")
      expect(Sowing::Infrastructure::Settings.load["vault_consent"]).to be true
    end
  end

  describe "단계 3: profile" do
    it "POST /onboarding/profile — user_name 저장" do
      post "/onboarding/profile", "user_name" => "김선생"
      expect(Sowing::Infrastructure::Settings.load["user_name"]).to eq("김선생")
      expect(last_response["Location"]).to end_with("/onboarding/samples")
    end

    it "빈 이름 → '선생님'으로 fallback" do
      post "/onboarding/profile", "user_name" => "  "
      expect(Sowing::Infrastructure::Settings.load["user_name"]).to eq("선생님")
    end
  end

  describe "단계 4: samples" do
    it "동의 (sample_consent=1) → completed 마킹 + done 페이지로" do
      post "/onboarding/samples", "sample_consent" => "1"
      settings = Sowing::Infrastructure::Settings.load
      expect(settings["sample_consent"]).to be true
      expect(settings["onboarding_completed"]).to be true
      expect(settings["completed_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(last_response["Location"]).to end_with("/onboarding/done")
    end

    it "건너뛰기 (sample_consent=0) → consent=false지만 completed 마킹" do
      post "/onboarding/samples", "sample_consent" => "0"
      settings = Sowing::Infrastructure::Settings.load
      expect(settings["sample_consent"]).to be false
      expect(settings["onboarding_completed"]).to be true
    end
  end

  describe "단계 5: done" do
    before do
      Sowing::Infrastructure::Settings.update(
        onboarding_completed: true, user_name: "이선생", sample_consent: true
      )
    end

    it "사용자 이름 인사 + 다음 행동 안내" do
      get "/onboarding/done"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("이선생")
      expect(last_response.body).to match(/Cmd|Ctrl|⌘/)
    end

    it "대시보드 진입 링크 포함" do
      get "/onboarding/done"
      expect(last_response.body).to include('href="/"')
    end
  end

  describe "전체 흐름 (5분 이내)" do
    it "welcome → vault → profile → samples → done 직선 진행" do
      get "/onboarding/welcome"
      expect(last_response.status).to eq(200)

      post "/onboarding/vault"
      follow_redirect!
      expect(last_request.path).to eq("/onboarding/profile")

      post "/onboarding/profile", "user_name" => "박교사"
      follow_redirect!
      expect(last_request.path).to eq("/onboarding/samples")

      post "/onboarding/samples", "sample_consent" => "1"
      follow_redirect!
      expect(last_request.path).to eq("/onboarding/done")

      # 이후 / 진입은 redirect 없음
      get "/"
      expect(last_response.status).to eq(200)
    end
  end
end
