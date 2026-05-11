# frozen_string_literal: true

require "rack/test"

# Phase 13 W26-T01 — 글쓰기 subtype 5종 (일반·책·강의·감정·학생).
# 도메인·use case·DB 변경 0 — client-side JS 가 body 결합. 본 spec 은:
#   1. /write/{subtype} 라우트 redirect + query param 보존
#   2. 모달 HTML 에 chip 5개 + slot field 4종 + 감정 18종 chip
#   3. nav 의 글쓰기 dropdown 에 subtype 진입점 4개
#   4. 서버 측 POST /memos 는 일반 메모와 동일 — 회귀 0
RSpec.describe "글쓰기 subtype (Phase 13 W26-T01)", type: :request do
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

  describe "빠른 메모 모달 — chip 5개 + slot field 4종" do
    it "5 subtype chip 모두 표시" do
      get "/"
      %w[general book lecture emotion student].each do |subtype|
        expect(last_response.body).to match(%r{data-subtype="#{subtype}"})
      end
    end

    it "각 chip 라벨 표시 (일반·책·강의·감정·학생)" do
      get "/"
      ["⚡ 일반", "📖 책", "🎤 강의", "💭 감정", "👤 학생"].each do |label|
        expect(last_response.body).to include(label)
      end
    end

    it "slot field 4종 (book/lecture/emotion/student)" do
      get "/"
      %w[book lecture emotion student].each do |subtype|
        expect(last_response.body).to match(%r{data-subtype-slot="#{subtype}"})
      end
    end

    it "책 slot — book_title + book_page" do
      get "/"
      expect(last_response.body).to include('data-slot-key="book_title"')
      expect(last_response.body).to include('data-slot-key="book_page"')
    end

    it "강의 slot — lecture_speaker + lecture_topic" do
      get "/"
      expect(last_response.body).to include('data-slot-key="lecture_speaker"')
      expect(last_response.body).to include('data-slot-key="lecture_topic"')
    end

    it "감정 slot — 18종 chip + hidden input" do
      get "/"
      expect(last_response.body).to include('data-slot-key="emotion"')
      # 18종 중 대표 8개 검증
      %w[설렘 기쁨 보람 답답 좌절 슬픔 그리움 기대].each do |emo|
        expect(last_response.body).to include(%(data-emotion="#{emo}"))
      end
    end

    it "학생 slot — student_name" do
      get "/"
      expect(last_response.body).to include('data-slot-key="student_name"')
    end
  end

  describe "nav 글쓰기 dropdown — 5 subtype 진입점" do
    it "각 subtype 의 /write/{type} 링크 노출" do
      get "/"
      %w[/write/book /write/lecture /write/emotion /write/student].each do |path|
        expect(last_response.body).to include(%(href="#{path}"))
      end
    end

    it "기존 메모/필기 진입점도 유지" do
      get "/"
      expect(last_response.body).to include('href="/memos"')
      expect(last_response.body).to include('href="/notes/new"')
      expect(last_response.body).to include('href="/notes"')
    end

    it "음성 입력 — W26-T02 예정 안내" do
      get "/"
      expect(last_response.body).to include("음성 입력")
      expect(last_response.body).to include("W26-T02")
    end
  end

  describe "POST /memos — 회귀 0 (subtype 무관 동일)" do
    let(:db) { Sowing::Infrastructure::DB.connection }
    let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }

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
