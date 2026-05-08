# frozen_string_literal: true

require "rack/test"

RSpec.describe "동기화 가이드 (W7-T05)", type: :request do
  include Rack::Test::Methods

  let(:expected_guides) { %w[sync_icloud sync_onedrive sync_dropbox sync_syncthing] }

  def app
    Sowing::Application
  end

  before { header "Host", "127.0.0.1" }

  describe "파일 존재 (ROADMAP 4종)" do
    it "templates/guides/ 에 4개 .md 파일" do
      expected_guides.each do |slug|
        path = File.join(Sowing.root, "templates/guides", "#{slug}.md")
        expect(File).to exist(path), "#{slug}.md 누락"
      end
    end

    it "각 가이드는 OS 지원 매트릭스 표 포함" do
      expected_guides.each do |slug|
        body = File.read(File.join(Sowing.root, "templates/guides", "#{slug}.md"))
        expect(body).to include("OS 지원 매트릭스"), "#{slug}: 매트릭스 헤더 누락"
        expect(body).to match(/\| .+ \| .+ \|/), "#{slug}: 마크다운 테이블 없음"
      end
    end

    it "각 가이드는 검증 단계와 주의사항 섹션 포함" do
      expected_guides.each do |slug|
        body = File.read(File.join(Sowing.root, "templates/guides", "#{slug}.md"))
        expect(body).to include("## 검증")
        expect(body).to include("## 주의")
      end
    end

    it "외부 링크는 https://" do
      expected_guides.each do |slug|
        body = File.read(File.join(Sowing.root, "templates/guides", "#{slug}.md"))
        non_https = body.scan(%r{http://[^\s)]+}).reject { |u| u.include?("localhost") }
        expect(non_https).to be_empty, "#{slug}: http:// 링크 #{non_https.inspect} (https 권장)"
      end
    end
  end

  describe "GET /guides" do
    before { get "/guides" }

    it "200 OK + 4개 가이드 모두 카드로 표시" do
      expect(last_response).to be_ok
      expected_guides.each { |slug| expect(last_response.body).to include(slug) }
    end

    it "라벨 표시 (iCloud/OneDrive/Dropbox/Syncthing)" do
      %w[iCloud OneDrive Dropbox Syncthing].each do |label|
        expect(last_response.body).to include(label)
      end
    end
  end

  describe "GET /guides/:slug" do
    it "각 가이드를 마크다운 → HTML로 렌더" do
      expected_guides.each do |slug|
        get "/guides/#{slug}"
        expect(last_response.status).to eq(200), "#{slug} 응답 #{last_response.status}"
        expect(last_response.body).to include("<h1>") # commonmarker 변환
        expect(last_response.body).to include("<table>") # OS 매트릭스
      end
    end

    it "없는 슬러그는 404" do
      get "/guides/sync_nonexistent"
      expect(last_response.status).to eq(404)
    end
  end
end
