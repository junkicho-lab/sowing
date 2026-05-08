# frozen_string_literal: true

require "rack/test"

RSpec.describe "Dashboard 라우트", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  # Sinatra 4의 host_authorization은 Rack::Test 기본 Host("example.org")를 거부.
  # Sowing은 로컬 우선이라 production에서 127.0.0.1만 허용 — test에서도 동일 호스트 사용.
  before do
    header "Host", "127.0.0.1"
    # 다른 spec이 entries를 남기면 빈 상태 CTA 검증이 깨지므로 정리.
    db = Sowing::Infrastructure::DB.connection
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  describe "GET /" do
    before { get "/" }

    it "200 OK를 반환한다" do
      expect(last_response).to be_ok
    end

    it "한국어 HTML 문서다 (lang='ko')" do
      expect(last_response.body).to include('<html lang="ko">')
    end

    it "UTF-8로 인코딩되어 있다" do
      expect(last_response.body).to include('<meta charset="UTF-8">')
    end

    it "Sowing 브랜드와 한국어 제목을 포함한다" do
      expect(last_response.body).to include("Sowing 🌱")
      expect(last_response.body).to include("대시보드 | Sowing")
    end

    it "오늘 날짜를 한국어 형식으로 표시한다" do
      expect(last_response.body).to match(/\d{4}년 \d{1,2}월 \d{1,2}일 [일월화수목금토]요일/)
    end

    it "빈 화면 금지 원칙에 따라 다음 행동(CLI 메모) CTA를 보여준다" do
      expect(last_response.body).to include("bin/sowing memo")
    end
  end

  describe "Hotwire 로딩" do
    before { get "/" }

    it "importmap에 Turbo와 Stimulus URL이 포함된다" do
      expect(last_response.body).to include("@hotwired/turbo")
      expect(last_response.body).to include("@hotwired/stimulus")
    end

    it "es-module-shims polyfill이 동봉된다 (구형 브라우저 대응)" do
      expect(last_response.body).to include("es-module-shims")
    end

    it "ESM import 스크립트가 들어 있다" do
      expect(last_response.body).to match(/import "@hotwired\/turbo"/)
      expect(last_response.body).to include("Application.start()")
    end
  end

  describe "정적 자원" do
    it "GET /css/application.css 가 정상 응답한다" do
      get "/css/application.css"
      expect(last_response).to be_ok
      expect(last_response.body).to include("--color-primary")
      expect(last_response.body).to include("#2D5F3F")
    end
  end

  describe "GET /health (시스템)" do
    before { get "/health" }

    it "JSON으로 status: ok를 반환한다" do
      expect(last_response).to be_ok
      expect(last_response.headers["content-type"]).to include("application/json")
      expect(last_response.body).to include('"status":"ok"')
    end
  end
end
