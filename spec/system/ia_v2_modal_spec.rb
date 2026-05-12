# frozen_string_literal: true

require "rack/test"

# Phase 13 W25-T02 — 동사 중심 nav 변경 안내 모달 (1회 표시).
RSpec.describe "동사 nav 안내 모달 (Phase 13 W25-T02)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    Sowing::Core::Settings.reset!
  end

  after { Sowing::Core::Settings.reset! }

  # 온보딩 완료 + ia_v2_seen_at 미설정 상태 시뮬레이션
  def setup_returning_user
    Sowing::Core::Settings.save(
      "onboarding_completed" => true,
      "ia_v2_seen_at" => nil
    )
  end

  describe "표시 조건" do
    it "온보딩 완료 + ia_v2_seen_at nil → 모달 표시" do
      setup_returning_user
      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('id="ia_v2_modal"')
      expect(last_response.body).to include("nav 가 더 직관적이 됐어요")
    end

    it "ia_v2_seen_at 설정됨 → 모달 표시 안 함" do
      Sowing::Core::Settings.save(
        "onboarding_completed" => true,
        "ia_v2_seen_at" => "2026-05-11T12:00:00+09:00"
      )
      get "/"
      expect(last_response.body).not_to include('id="ia_v2_modal"')
    end

    it "온보딩 미완료 → 모달 표시 안 함 (튜토리얼 우선)" do
      Sowing::Core::Settings.save(
        "onboarding_completed" => false,
        "ia_v2_seen_at" => nil
      )
      # 온보딩 미완료 시 / 진입은 자동 /onboarding/welcome 으로 redirect 됨
      get "/"
      expect(last_response.status).to eq(302)
    end

    it "/onboarding/* 경로 → 모달 표시 안 함" do
      Sowing::Core::Settings.save(
        "onboarding_completed" => false,
        "ia_v2_seen_at" => nil
      )
      get "/onboarding/welcome"
      expect(last_response.body).not_to include('id="ia_v2_modal"')
    end

    it "/tutorial/* 경로 → 모달 표시 안 함" do
      setup_returning_user
      get "/tutorial"
      expect(last_response.body).not_to include('id="ia_v2_modal"') if last_response.status == 200
    end
  end

  describe "모달 내용" do
    before { setup_returning_user }

    it "4개 동사 dropdown 안내" do
      get "/"
      %w[글쓰기 쓴\ 글\ 보기 쓸\ 글\ 계획 자기\ 거울].each do |label|
        expect(last_response.body).to include(label)
      end
    end

    it "REDESIGN_IA.md 링크 (배경 안내)" do
      get "/"
      expect(last_response.body).to include("REDESIGN_IA.md")
    end

    it "'이해했습니다 — 시작하기' CTA 버튼" do
      get "/"
      expect(last_response.body).to include("이해했습니다")
    end
  end

  describe "POST /settings/dismiss-ia-v2 — 닫기" do
    before { setup_returning_user }

    it "AJAX 호출 시 JSON 응답 + ia_v2_seen_at 기록" do
      post "/settings/dismiss-ia-v2", {}, {"HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"}
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('"status":"ok"')

      settings = Sowing::Core::Settings.load
      expect(settings["ia_v2_seen_at"]).not_to be_nil
      expect(settings["ia_v2_seen_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "JS 비활성화 form fallback — redirect 후 다음 진입에 모달 안 보임" do
      post "/settings/dismiss-ia-v2"
      expect(last_response.status).to eq(302)

      # 다음 GET 진입 — 모달 사라짐
      get "/"
      expect(last_response.body).not_to include('id="ia_v2_modal"')
    end

    it "닫은 후 다시 진입해도 모달 안 보임 (1회 약속)" do
      post "/settings/dismiss-ia-v2", {}, {"HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"}

      %w[/ /memos /records /synth /tags].each do |path|
        get path
        expect(last_response.body).not_to include('id="ia_v2_modal"'),
          "#{path} 에서 모달이 다시 표시됨"
      end
    end
  end

  describe "Settings 통합" do
    it "DEFAULTS 에 ia_v2_seen_at: nil 포함" do
      Sowing::Core::Settings.reset!
      settings = Sowing::Core::Settings.load
      expect(settings).to have_key("ia_v2_seen_at")
      expect(settings["ia_v2_seen_at"]).to be_nil
    end

    it "update 로 ia_v2_seen_at 설정 가능" do
      Sowing::Core::Settings.update(ia_v2_seen_at: "2026-05-11T12:00:00+09:00")
      expect(Sowing::Core::Settings.load["ia_v2_seen_at"]).to eq("2026-05-11T12:00:00+09:00")
    end
  end
end
