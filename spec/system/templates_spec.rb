# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "템플릿 라우트 (W6-T04)", type: :request do
  include Rack::Test::Methods

  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }
  let(:templates_dir) { vault_dir.join("templates") }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    FileUtils.rm_rf(templates_dir)
  end

  describe "GET /templates" do
    it "빈 상태 안내" do
      get "/templates"
      expect(last_response).to be_ok
      expect(last_response.body).to include("아직 템플릿이 없습니다")
    end

    it "기존 템플릿 목록 표시" do
      FileUtils.mkdir_p(templates_dir)
      File.write(templates_dir.join("수업회고.md"), "오늘 수업\n돌아보기")

      get "/templates"
      expect(last_response.body).to include("수업회고")
      expect(last_response.body).to include("오늘 수업")
    end
  end

  describe "POST /templates (저장)" do
    it "정상 입력 → 302 redirect + 파일 생성" do
      post "/templates", "slug" => "회고", "content" => "오늘은 {{date}}"
      expect(last_response.status).to eq(302)
      expect(templates_dir.join("회고.md").read).to include("{{date}}")
    end

    it "빈 슬러그 → 422 + 에러 메시지" do
      post "/templates", "slug" => "", "content" => "본문"
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("이름을 입력")
    end

    it "유효하지 않은 슬러그 → 422" do
      post "/templates", "slug" => "with space", "content" => "본문"
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("한글/영문")
    end

    it "빈 본문 → 422" do
      post "/templates", "slug" => "회고", "content" => "  "
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("본문을 입력")
    end
  end

  describe "GET /templates/:slug" do
    before do
      FileUtils.mkdir_p(templates_dir)
      File.write(templates_dir.join("회고.md"), "# 작성일\n{{date_korean}}\n\n{{user}}님의 메모")
    end

    it "원본 + 치환 미리보기 양쪽 표시" do
      get "/templates/#{Rack::Utils.escape("회고")}"
      expect(last_response).to be_ok
      expect(last_response.body).to include("{{date_korean}}")              # 원본 placeholder
      expect(last_response.body).to match(/\d{4}년 \d{1,2}월 \d{1,2}일/)     # 치환된 한국어 날짜
      expect(last_response.body).to include("{{user}}")                     # 치환 안 된 unknown은 유지
    end

    it "없는 슬러그는 404" do
      get "/templates/#{Rack::Utils.escape("없음")}"
      expect(last_response.status).to eq(404)
    end
  end

  describe "헤더 네비게이션" do
    it "/templates 링크 표시" do
      get "/"
      expect(last_response.body).to include('<a href="/templates">템플릿</a>')
    end
  end
end
