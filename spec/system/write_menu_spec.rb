# frozen_string_literal: true

require "rack/test"

# 글쓰기 nav 메뉴 정비 — 빠른메모/빠른기록 + 메모목록/기록목록 만 노출.
RSpec.describe "글쓰기 메뉴 (Phase 16 nav cleanup)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before { header "Host", "127.0.0.1"; get "/" }

  let(:body) { last_response.body }

  describe "유지된 항목" do
    it "⚡ 빠른 메모 (modal 트리거)" do
      expect(body).to include("⚡ 빠른 메모")
      expect(body).to include("data-quick-memo-target=&quot;dialog&quot;")
    end

    it "⚡ 빠른 기록 (modal 트리거)" do
      expect(body).to include("⚡ 빠른 기록")
      expect(body).to include("quick_record_modal")
    end

    it "📂 메모 목록 (/memos)" do
      expect(body).to include("📂 메모 목록")
      expect(body).to match(%r{href="/memos"})
    end

    it "📂 기록 목록 (/records)" do
      expect(body).to include("📂 기록 목록")
      expect(body).to match(%r{href="/records"})
    end
  end

  describe "제거된 항목 (메뉴에서만 — 라우트는 호환 유지)" do
    it "📖 책 기록 메뉴 항목 없음" do
      expect(body).not_to include("📖 책 기록")
    end

    it "🎤 강의·연수 없음" do
      expect(body).not_to include("🎤 강의·연수")
    end

    it "💭 감정 기록 없음" do
      expect(body).not_to include("💭 감정 기록")
    end

    it "👤 학생 관찰 메뉴 항목 없음 (다른 곳 'student' 매칭 무관)" do
      # 메뉴 영역만 정확히 검증 — 동일 텍스트의 다른 등장은 OK
      expect(body).not_to include('href="/write/student"')
    end

    it "📝 필기 작성 (메뉴에서) 없음" do
      expect(body).not_to include("📝 필기 작성")
    end

    it "📂 필기 목록 (메뉴에서) 없음" do
      expect(body).not_to include("📂 필기 목록")
    end
  end

  describe "옛 /write/:subtype 라우트는 옛 북마크 호환용 유지" do
    %w[book lecture emotion student general].each do |subtype|
      it "/write/#{subtype} → 303 redirect (호환)" do
        get "/write/#{subtype}"
        expect(last_response.status).to be_between(302, 303)
        expect(last_response.location).to include("/?write=#{subtype}")
      end
    end
  end

  describe "/notes 라우트는 살아있음 (메뉴 제거와 무관)" do
    it "/notes/new GET 200" do
      get "/notes/new"
      expect(last_response.status).to eq(200)
    end

    it "/notes GET 200" do
      get "/notes"
      expect(last_response.status).to eq(200)
    end
  end

  describe "빠른 기록 모달 노출" do
    it "<dialog id='quick_record_modal'> 가 layout 에 포함됨" do
      expect(body).to include('id="quick_record_modal"')
    end

    it "폼이 POST /records 로 제출" do
      expect(body).to match(%r{<form action="/records" method="post"})
    end

    it "title / category / body 필드 모두 required" do
      expect(body).to match(/name="title"[^>]+required/)
      expect(body).to match(/name="category"[^>]+required/)
      expect(body).to match(/name="body"[^>]+required/)
    end

    it "카테고리 datalist 자동완성 노출" do
      expect(body).to include('list="quick_record_category_list"')
      expect(body).to include('<datalist id="quick_record_category_list">')
    end
  end

  describe "POST /records 모달 제출 → 새 기록 페이지로 redirect" do
    let(:db) { Sowing::Core::DB.connection }
    before do
      db[:entry_tags].delete
      db[:tags].delete
      db[:entries_fts].delete
      db[:entries].delete
      vault = Sowing::Core::Paths.vault_dir
      FileUtils.rm_rf(vault.join("30_Records"))
    end

    it "정상 입력 → 새 record show 페이지로 303" do
      post "/records",
        "title" => "1학기 1단원 정리",
        "body" => "내용",
        "category" => "수업기록"
      expect(last_response.status).to be_between(302, 303)
      expect(last_response.location).to match(%r{/records/\w+})
    end

    it "title 누락 → 422 + 폼 재표시" do
      post "/records", "title" => "", "body" => "x", "category" => "x"
      expect(last_response.status).to eq(422)
    end
  end
end
