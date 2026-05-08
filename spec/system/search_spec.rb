# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "검색 화면 (W4-T03)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    FileUtils.rm_rf(vault_dir.join("00_Inbox"))
    FileUtils.rm_rf(vault_dir.join("20_Notes"))
    FileUtils.rm_rf(vault_dir.join("30_Records"))
  end

  describe "GET /search (필터 없음)" do
    before { get "/search" }

    it "200 OK + 검색 폼만 표시 (결과 없음)" do
      expect(last_response).to be_ok
      expect(last_response.body).to include("검색")
      expect(last_response.body).to include('name="q"')
      expect(last_response.body).to include('name="mode"')
      expect(last_response.body).to include('name="category"')
      expect(last_response.body).to include('name="tag"')
      expect(last_response.body).to include('name="from"')
      expect(last_response.body).to include('name="to"')
    end

    it "총 N건 표시 안 함 (검색 시도 X)" do
      expect(last_response.body).not_to include("총 0건")
    end

    it "모드 select에 4가지 옵션 (전체/메모/필기/기록)" do
      expect(last_response.body).to include('value=""') # 전체
      expect(last_response.body).to include('value="memo"')
      expect(last_response.body).to include('value="note"')
      expect(last_response.body).to include('value="record"')
    end
  end

  describe "기본 검색" do
    before do
      post "/memos", body: "오늘 1교시 협동학습 활기"
      post "/notes",
        "title" => "협동학습 정리",
        "body" => "본문",
        "category" => "trainings",
        "source" => "연수"
      post "/records",
        "title" => "5월 회고",
        "body" => "이번 달 돌아보기",
        "category" => "학급운영"
    end

    it "한국어 query는 LIKE 폴백 — 2글자도 매칭" do
      get "/search", q: "회고"
      expect(last_response.body).to include("총 1건")
      expect(last_response.body).to include("5월 회고")
    end

    it "본문 검색도 동작" do
      get "/search", q: "협동학습"
      expect(last_response.body).to include("협동학습 정리") # note title
      expect(last_response.body.scan('class="search-result"').size).to be >= 2
    end

    it "매칭 없으면 안내 메시지" do
      get "/search", q: "절대없는키워드"
      expect(last_response.body).to include("조건에 맞는 항목이 없습니다")
    end
  end

  describe "모드 필터" do
    before do
      post "/memos", body: "메모 협동학습"
      post "/notes",
        "title" => "필기 협동학습",
        "body" => "본문",
        "category" => "trainings",
        "source" => "연수"
    end

    it "?mode=note → 필기만" do
      get "/search", q: "협동학습", mode: "note"
      expect(last_response.body).to include("총 1건")
      expect(last_response.body).to include("필기 협동학습")
      expect(last_response.body).not_to include("메모 협동학습")
    end

    it "?mode=memo → 메모만" do
      get "/search", q: "협동학습", mode: "memo"
      expect(last_response.body).to include("총 1건")
    end

    it "잘못된 mode는 무시 (전체로)" do
      get "/search", q: "협동학습", mode: "alien"
      expect(last_response.body).to include("총 2건")
    end
  end

  describe "카테고리 필터" do
    before do
      post "/notes",
        "title" => "수업 1",
        "body" => "본문",
        "category" => "lessons",
        "source" => "교과서"
      post "/notes",
        "title" => "연수 1",
        "body" => "본문",
        "category" => "trainings",
        "source" => "연수"
    end

    it "?category=lessons → 해당 카테고리만" do
      get "/search", category: "lessons"
      expect(last_response.body).to include("수업 1")
      expect(last_response.body).not_to include("연수 1")
    end
  end

  describe "태그 필터" do
    before do
      post "/memos", body: "본문 #수업 #1학년"
      post "/memos", body: "본문 #수업"
      post "/memos", body: "본문 #복습"
    end

    it "?tag=수업 → 수업 태그를 가진 entries" do
      get "/search", tag: "수업"
      expect(last_response.body).to include("총 2건")
    end

    it "태그는 case-insensitive (TagSet 정책)" do
      post "/memos", body: "#ENGLISH"
      get "/search", tag: "english"
      expect(last_response.body).to include("총 1건")
    end
  end

  describe "날짜 범위 필터" do
    let(:db) { Sowing::Infrastructure::DB.connection }

    before do
      # iso8601 직접 INSERT — POST /memos는 Time.now 사용하므로 날짜 컨트롤이 어려워 raw SQL 사용
      [
        ["01KR1AAAAAAAAAAAAAAAAAAA00", "2026-04-01T09:00:00+09:00", "00_Inbox/a.md"],
        ["01KR1AAAAAAAAAAAAAAAAAAA01", "2026-05-08T09:00:00+09:00", "00_Inbox/b.md"],
        ["01KR1AAAAAAAAAAAAAAAAAAA02", "2026-06-15T09:00:00+09:00", "00_Inbox/c.md"]
      ].each do |id, ts, path|
        db[:entries].insert(
          id: id, path: path, mode: "memo",
          created_at: ts, updated_at: ts,
          file_mtime: 0, file_hash: "deadbeef00000000",
          word_count: 0, indexed_at: ts
        )
        db[:entries_fts].insert(id: id, title: nil, body: "본문 #{id}")
      end
    end

    it "from·to 범위 (양 끝 inclusive)" do
      get "/search", from: "2026-05-01", to: "2026-05-31"
      expect(last_response.body).to include("총 1건")
    end

    it "넓은 범위" do
      get "/search", from: "2026-01-01", to: "2026-12-31"
      expect(last_response.body).to include("총 3건")
    end

    it "잘못된 날짜 형식은 무시" do
      get "/search", from: "not-a-date", to: "also-bad"
      # 다른 필터도 없으므로 검색 시도 안 함 → 결과 없음
      expect(last_response.body).not_to include("총 ")
    end
  end

  describe "복합 필터 (AND 결합)" do
    before do
      post "/notes",
        "title" => "수업 정리 1",
        "body" => "본문",
        "category" => "lessons",
        "source" => "교과서",
        "tags" => "수업"
      post "/notes",
        "title" => "연수 정리",
        "body" => "본문",
        "category" => "trainings",
        "source" => "연수",
        "tags" => "수업"
      post "/memos", body: "메모 #수업"
    end

    it "mode + tag 조합" do
      get "/search", mode: "note", tag: "수업"
      expect(last_response.body).to include("총 2건")
    end

    it "mode + tag + category 조합" do
      get "/search", mode: "note", tag: "수업", category: "lessons"
      expect(last_response.body).to include("총 1건")
      expect(last_response.body).to include("수업 정리 1")
    end

    it "q + mode 조합" do
      get "/search", q: "수업", mode: "memo"
      expect(last_response.body).to include("총 1건")
    end
  end

  describe "결과 표시" do
    before do
      post "/notes",
        "title" => "필기 제목",
        "body" => "본문",
        "category" => "lessons",
        "source" => "교과서"
    end

    it "각 항목은 모드 아이콘과 메타 정보 표시" do
      get "/search", q: "필기 제목"
      expect(last_response.body).to include("📝") # note icon
      expect(last_response.body).to include("필기")
      expect(last_response.body).to include("lessons")
    end

    it "note는 /notes/:id 링크" do
      get "/search", q: "필기 제목"
      note_id = db[:entries].where(mode: "note").first[:id]
      expect(last_response.body).to include("/notes/#{note_id}")
    end
  end

  describe "페이지네이션" do
    before do
      31.times { |i| post "/memos", body: "검색가능한본문 #{i}" }
    end

    it "첫 페이지 30건 + 페이지네이션 표시" do
      get "/search", q: "검색가능한본문"
      expect(last_response.body.scan('class="search-result"').size).to eq(30)
      expect(last_response.body).to include("1 / 2")
    end

    it "?page=2 → 2페이지 1건" do
      get "/search", q: "검색가능한본문", page: "2"
      expect(last_response.body).to include("2 / 2")
      expect(last_response.body.scan('class="search-result"').size).to eq(1)
    end

    it "page link에 다른 필터들도 보존됨" do
      get "/search", q: "검색가능한본문", mode: "memo"
      expect(last_response.body).to match(/href="\/search\?[^"]*page=2[^"]*mode=memo|mode=memo[^"]*page=2/)
    end
  end

  describe "필터 초기화" do
    it "필터가 적용된 페이지에 '필터 초기화' 링크" do
      get "/search", q: "test"
      expect(last_response.body).to include("필터 초기화")
      expect(last_response.body).to include('href="/search"')
    end

    it "필터 없으면 초기화 링크 안 보임" do
      get "/search"
      expect(last_response.body).not_to include("필터 초기화")
    end
  end

  describe "내비게이션" do
    it "헤더의 '검색' 링크가 활성화" do
      get "/"
      expect(last_response.body).to include('<a href="/search">검색</a>')
    end
  end
end
