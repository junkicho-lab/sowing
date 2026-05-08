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
    it "기본 12종 시스템 템플릿이 항상 노출됨 (W6-T05)" do
      get "/templates"
      expect(last_response).to be_ok
      %w[lesson_reflection student_observation parent_counseling meeting_notes
        training_notes book_notes classroom_journal peer_observation
        assessment_analysis career_counseling school_event free_journal].each do |slug|
        expect(last_response.body).to include(slug)
      end
      # 시스템 배지
      expect(last_response.body).to include("기본")
    end

    it "사용자 템플릿이 추가되면 함께 표시 + 사용자 배지" do
      FileUtils.mkdir_p(templates_dir)
      File.write(templates_dir.join("나만의것.md"), "사용자")
      get "/templates"
      expect(last_response.body).to include("나만의것")
      expect(last_response.body).to include("사용자")
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

  describe "12종 시스템 템플릿 (W6-T05 SPEC §4.1 F8)" do
    let(:expected) {
      %w[
        lesson_reflection student_observation parent_counseling meeting_notes
        training_notes book_notes classroom_journal peer_observation
        assessment_analysis career_counseling school_event free_journal
      ]
    }

    it "12개 모두 templates/ 디렉토리에 존재" do
      project_root = Sowing.root
      expected.each do |slug|
        path = File.join(project_root, "templates", "#{slug}.md")
        expect(File).to exist(path), "템플릿 누락: #{slug}.md"
      end
    end

    it "각 템플릿은 GET /templates/:slug 로 렌더 가능 (placeholder 치환 포함)" do
      expected.each do |slug|
        get "/templates/#{slug}"
        expect(last_response.status).to eq(200), "#{slug} 응답 #{last_response.status}"
        expect(last_response.body).to match(/\d{4}년 \d{1,2}월 \d{1,2}일|\d{4}-\d{2}-\d{2}/), "#{slug} 미리보기에 날짜 없음"
      end
    end

    it "각 템플릿은 H1 제목과 적절한 태그를 포함 (옵시디언 호환)" do
      project_root = Sowing.root
      expected.each do |slug|
        content = File.read(File.join(project_root, "templates", "#{slug}.md"))
        expect(content).to match(/^# /), "#{slug}에 H1 헤딩 없음"
        expect(content).to match(/#[가-힣]+/), "#{slug}에 한글 태그 없음"
      end
    end
  end

  describe "헤더 네비게이션" do
    it "/templates 링크 표시" do
      get "/"
      expect(last_response.body).to include('<a href="/templates">템플릿</a>')
    end
  end
end
