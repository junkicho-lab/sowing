# frozen_string_literal: true

require "rack/test"

# Phase 13 W25-T01 — 동사 중심 nav (5+1) PoC 검증.
# REDESIGN_IA.md 의 새 IA 가 동작하면서 기존 라우트가 모두 그대로 작동하는지.
RSpec.describe "동사 중심 nav (Phase 13 W25-T01)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before { header "Host", "127.0.0.1" }

  describe "GET / — nav 5+1 동사 표시" do
    it "5개 1급 동사 + 홈·설정 표시" do
      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("🏠 홈")
      expect(last_response.body).to include("🖊 글쓰기")
      expect(last_response.body).to include("📚 쓴 글 보기")
      expect(last_response.body).to include("🗓 쓸 글 계획")
      expect(last_response.body).to include("🪞 자기 거울")
      expect(last_response.body).to include("⚙ 설정")
    end

    it "<details> dropdown 구조 — JS 0" do
      get "/"
      # 4 dropdown 1급 (글쓰기·쓴글보기·쓸글계획·자기거울) + 1 more = 5 details
      expect(last_response.body.scan(%r{<details class="nav-v2__group}).size).to be >= 5
    end

    it "글쓰기 dropdown — 빠른 메모·필기 진입점" do
      get "/"
      expect(last_response.body).to include("⚡ 빠른 메모")
      expect(last_response.body).to include("💭 메모 목록")
      expect(last_response.body).to include("📝 필기 작성")
      expect(last_response.body).to include("W26 예정") # 음성·subtype 안내
    end

    it "쓴 글 보기 dropdown — 회상 9가지 통합" do
      get "/"
      expect(last_response.body).to include("📁 기록 (카테고리별)")
      expect(last_response.body).to include("📊 카테고리 × 연도")
      expect(last_response.body).to include("📅 Timeline")
      expect(last_response.body).to include("🏷 태그")
      expect(last_response.body).to include("🕸 위키링크 그래프")
      expect(last_response.body).to include("🔍 검색")
    end

    it "쓸 글 계획 — W27 예정 안내" do
      get "/"
      expect(last_response.body).to include("Phase 13 W27 예정")
    end

    it "자기 거울 — 합성기 + 사용 지표 + W28 예정" do
      get "/"
      expect(last_response.body).to include("🌱 합성기 16종")
      expect(last_response.body).to include("📊 사용 지표")
      expect(last_response.body).to include("W28 예정")
    end
  end

  describe "신규 통합 진입 라우트 (W25-T01 stub)" do
    it "GET /write → /memos redirect" do
      get "/write"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/memos")
    end

    it "GET /view → /records redirect" do
      get "/view"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/records")
    end

    it "GET /plan → /settings redirect + flash 안내" do
      get "/plan"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/settings")
      # 다음 요청 시 flash 노출 확인
      follow_redirect!
      expect(last_response.body).to include("W27")
    end

    it "GET /mirror → /synth redirect" do
      get "/mirror"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "기존 명사 라우트 — 100% 그대로 작동 (regression)" do
    %w[/ /memos /notes /records /tags /search /templates /synth /graph /settings
       /records/by-category /records/timeline /synth/metrics].each do |path|
      it "GET #{path} — 정상 응답" do
        get path
        expect(last_response.status).to be_between(200, 399).inclusive,
          "#{path} returned #{last_response.status}"
      end
    end
  end
end
