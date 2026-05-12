# frozen_string_literal: true

require "rack/test"

# Phase 13 W26-T01 의 5 subtype slot 시스템 (책·강의·감정·학생) 은 2026-05-12 에
# 4축 분류 chip (ADR-016 — 인물·교과·문서·정체성) 으로 교체되었음.
# 본 spec 은:
#   1. /write/{subtype} 라우트는 옛 북마크 호환용으로 살아있음
#   2. 모달 HTML 에 새 4축 chip 5개 (일반 + 4축)
#   3. 옛 slot field (book/lecture/emotion/student) 미노출 — 회귀 방지
#   4. POST /memos 는 subject ENUM 수신 (일반 = 미지정)
RSpec.describe "빠른 메모 모달 — 4축 chip (ADR-016, 2026-05-12)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  before { header "Host", "127.0.0.1" }

  describe "GET /write/{subtype} redirect" do
    %w[general book lecture emotion student].each do |subtype|
      it "/write/#{subtype} → / + ?write=#{subtype}" do
        get "/write/#{subtype}"
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include("write=#{subtype}")
      end
    end

    it "잘못된 subtype → general 폴백 (allowlist 보안)" do
      get "/write/evil-injection"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include("write=general")
    end

    it "/write (subtype 없음) → general" do
      get "/write"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include("write=general")
    end
  end

  describe "빠른 메모 모달 — 4축 chip 5개 (일반 + 인물/교과/문서/정체성)" do
    it "5 chip (일반 + 4축) 모두 표시" do
      get "/"
      ["", "person", "subject", "document", "identity"].each do |subj|
        expect(last_response.body).to match(%r{data-subject="#{subj}"})
      end
    end

    it "각 chip 라벨 표시 (일반·인물·교과·문서·정체성)" do
      get "/"
      ["⚡ 일반", "👤 인물", "📚 교과", "📄 문서", "🪞 정체성"].each do |label|
        expect(last_response.body).to include(label)
      end
    end

    it "hidden subject input 노출 (chip 으로 갱신)" do
      get "/"
      expect(last_response.body).to match(%r{<input type="hidden" name="subject"})
      expect(last_response.body).to include('data-quick-memo-target="subjectInput"')
    end

    it "옛 slot field (book/lecture/emotion/student) 미노출 — 회귀 방지" do
      get "/"
      %w[book_title book_page lecture_speaker lecture_topic student_name].each do |slot|
        expect(last_response.body).not_to include(%(data-slot-key="#{slot}"))
      end
    end

    it "옛 감정 chip 18종 미노출" do
      get "/"
      expect(last_response.body).not_to include('data-emotion="설렘"')
      expect(last_response.body).not_to include('data-emotion="기쁨"')
    end

    it "옛 4축 분류 <select> dropdown 미노출 — chip 으로 교체됨" do
      get "/"
      expect(last_response.body).not_to include('class="quick-modal__subject-select"')
      expect(last_response.body).not_to include('class="quick-modal__subject-label"')
    end
  end

  # 글쓰기 메뉴 정비 (사용자 요청, 2026-05-12) — 4 subtype 단축링크와 필기 진입점은
  # 메뉴에서 제거되었으나 /write/:subtype 라우트는 호환용으로 살아있음.
  # 모달 내부의 subtype chip 은 그대로 유지 (모달 기능 자체는 변함 없음).
  describe "nav 글쓰기 dropdown — 정비된 메뉴" do
    it "subtype 단축링크는 메뉴에서 제거됨" do
      get "/"
      %w[/write/book /write/lecture /write/emotion /write/student].each do |path|
        expect(last_response.body).not_to include(%(href="#{path}"))
      end
    end

    it "필기 진입점도 메뉴에서 제거됨 (/notes 라우트 자체는 호환)" do
      get "/"
      expect(last_response.body).not_to include('href="/notes/new"')
      # 메뉴의 직접 /notes 링크는 없음 — 다른 곳 (예: edit 페이지 footer) 의 링크는 OK
    end

    it "/write/:subtype 라우트는 옛 북마크용으로 살아있음" do
      get "/write/book"
      expect(last_response.status).to be_between(302, 303)
      expect(last_response.location).to include("?write=book")
    end
  end

  describe "POST /memos — 회귀 0 (subtype 무관 동일)" do
    let(:db) { Sowing::Core::DB.connection }
    let(:vault_dir) { Sowing::Core::Paths.vault_dir }

    before do
      db[:entries_fts].delete
      db[:links].delete
      db[:entry_tags].delete
      db[:tags].delete
      db[:entries].delete
      FileUtils.rm_rf(vault_dir.join("00_Inbox"))
    end

    it "subtype 정보 없이 일반 body 만 보내도 정상 저장" do
      post "/memos", body: "오늘 1교시 협동학습 도입 #회고"
      expect(last_response.status).to be_between(200, 399).inclusive
      expect(db[:entries].where(mode: "memo").count).to eq(1)
    end

    it "subtype 결합된 body (책 형식) 도 정상 저장 + vault 파일에 본문 포함" do
      body = "**📖 책:** 사피엔스\n**페이지:** 42\n\n인간만이 허구를 믿는다.\n\n#책기록"
      post "/memos", body: body
      expect(last_response.status).to be_between(200, 399).inclusive
      memo = db[:entries].where(mode: "memo").first
      expect(memo).not_to be_nil
      # body 는 entries 테이블이 아니라 vault file + FTS5 가상 테이블에 저장.
      # vault file 의 본문에 사피엔스·#책기록 모두 포함 확인.
      file_content = File.read(vault_dir.join(memo[:path]))
      expect(file_content).to include("사피엔스")
      expect(file_content).to include("#책기록")
    end
  end
end
