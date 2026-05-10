# frozen_string_literal: true

# 30년 시나리오 — `/records/timeline` + `/records/by-category` 라우트.
# 폴더 무관 cross-year 탐색 + 카테고리 매트릭스.

require "rack/test"
require "fileutils"

RSpec.describe "기록 cross-year 라우트 (30년 시나리오)", type: :request do
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
    FileUtils.rm_rf(vault_dir.join("30_Records"))
  end

  let(:seed_counter) { @seed_counter ||= [0] }
  def seed_record(title:, category:, created_at:)
    seed_counter[0] += 1
    rid = "01CRSYEAR" + format("%017d", seed_counter[0])
    year = created_at[0, 4]
    path = "30_Records/#{year}/#{category}/rec-#{seed_counter[0]}.md"
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    File.write(abs, "---\nid: #{rid}\nmode: record\ncategory: #{category}\ntitle: #{title}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\n---\n\n본문 #{title}\n")

    db[:entries].insert(
      id: rid, path: path, mode: "record",
      category: category, title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: 2, indexed_at: created_at
    )

    # FTS5 가상 테이블에 추가 (FTS 검색 spec 위해)
    db[:entries_fts].insert(id: rid, body: "본문 #{title}", title: title)
  end

  def esc(s)
    Rack::Utils.escape(s)
  end

  describe "GET /records/timeline" do
    before do
      seed_record(title: "분수 단원 회고", category: "수업회고", created_at: "2024-03-10T09:00:00+09:00")
      seed_record(title: "협동학습 정착", category: "수업회고", created_at: "2025-04-15T09:00:00+09:00")
      seed_record(title: "학부모 면담", category: "상담", created_at: "2024-05-20T09:00:00+09:00")
      seed_record(title: "단원평가 분석", category: "평가", created_at: "2026-06-25T09:00:00+09:00")
    end

    it "200 OK + 모든 record 시간순 (default desc)" do
      get "/records/timeline"
      expect(last_response).to be_ok
      expect(last_response.body).to include("기록 Timeline")
      expect(last_response.body).to include("총 <strong>4</strong>건")
      expect(last_response.body).to include("단원평가 분석")
      expect(last_response.body).to include("분수 단원 회고")
    end

    it "연도 헤더 자동 삽입 — cross-year 시각화" do
      get "/records/timeline"
      expect(last_response.body).to include("2026년")
      expect(last_response.body).to include("2025년")
      expect(last_response.body).to include("2024년")
    end

    it "다중 카테고리 필터 — categories[]" do
      get "/records/timeline?categories[]=#{esc("수업회고")}&categories[]=#{esc("평가")}"
      expect(last_response.body).to include("총 <strong>3</strong>건")
      expect(last_response.body).to include("분수 단원 회고")
      expect(last_response.body).to include("단원평가 분석")
      expect(last_response.body).not_to include("학부모 면담")
    end

    it "키워드 검색 (FTS5)" do
      get "/records/timeline?q=#{esc("분수")}"
      expect(last_response).to be_ok
      # FTS5 가 한글 trigram 으로 매칭 — 분수 분수단원 둘 다 포함
      expect(last_response.body).to match(/분수/)
    end

    it "since/until 날짜 범위" do
      get "/records/timeline?since=2025-01-01&until=2025-12-31"
      expect(last_response.body).to include("총 <strong>1</strong>건")
      expect(last_response.body).to include("협동학습 정착")
      expect(last_response.body).not_to include("분수 단원 회고")
    end

    it "정렬 oldest first (asc)" do
      get "/records/timeline?order=asc"
      expect(last_response).to be_ok
      # 2024년이 2026년 보다 먼저 등장
      idx_2024 = last_response.body.index("2024년")
      idx_2026 = last_response.body.index("2026년")
      expect(idx_2024).to be < idx_2026
    end

    it "결과 0건 — 빈 상태 안내" do
      get "/records/timeline?since=1900-01-01&until=1900-12-31"
      expect(last_response.body).to include("조건에 맞는 기록이 없습니다")
    end

    it "/records/timeline 라우트가 /records/:id 보다 우선 매칭" do
      # timeline 이 :id 로 잡히면 not_found 가 떠야 함. 우선이면 timeline view.
      get "/records/timeline"
      expect(last_response).to be_ok
      expect(last_response.body).to include("Timeline")
      expect(last_response.body).not_to include("찾을 수 없")
    end
  end

  describe "GET /records/by-category" do
    before do
      seed_record(title: "a1", category: "수업회고", created_at: "2024-03-10T09:00:00+09:00")
      seed_record(title: "a2", category: "수업회고", created_at: "2024-04-15T09:00:00+09:00")
      seed_record(title: "a3", category: "수업회고", created_at: "2025-05-20T09:00:00+09:00")
      seed_record(title: "b1", category: "상담", created_at: "2024-06-01T09:00:00+09:00")
      seed_record(title: "b2", category: "상담", created_at: "2026-07-01T09:00:00+09:00")
    end

    it "200 OK + 매트릭스 표시 + 카테고리·연도·셀 카운트" do
      get "/records/by-category"
      expect(last_response).to be_ok
      expect(last_response.body).to include("카테고리 × 연도 매트릭스")
      expect(last_response.body).to include("총 <strong>5</strong>건")
      # 카테고리
      expect(last_response.body).to include("수업회고")
      expect(last_response.body).to include("상담")
      # 연도 헤더
      expect(last_response.body).to include("2024")
      expect(last_response.body).to include("2025")
      expect(last_response.body).to include("2026")
    end

    it "셀이 timeline 으로 drill-down 링크" do
      get "/records/by-category"
      # 수업회고 + 2024년 셀 → /records/timeline 링크
      expect(last_response.body).to include("/records/timeline?categories[]=")
      expect(last_response.body).to include("since=2024-01-01")
      expect(last_response.body).to include("until=2024-12-31")
    end

    it "비어 있음 — 안내" do
      db[:entries].delete
      get "/records/by-category"
      expect(last_response.body).to include("아직 기록이 없습니다")
    end
  end

  describe "GET /records (인덱스 뷰 링크)" do
    it "timeline / by-category 진입 링크 표시" do
      get "/records"
      expect(last_response.body).to include('href="/records/timeline"')
      expect(last_response.body).to include('href="/records/by-category"')
    end
  end
end
