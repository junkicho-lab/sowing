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
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    db[:daily_stats].delete
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

  describe "통계 위젯 (W6-T02)" do
    let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }

    before do
      FileUtils.rm_rf(vault_dir.join("00_Inbox"))
      FileUtils.rm_rf(vault_dir.join("20_Notes"))
      FileUtils.rm_rf(vault_dir.join("30_Records"))
    end

    it "빈 상태 — 모든 카운트가 0, streak도 0 ('오늘부터 시작!' 표시)" do
      get "/"
      expect(last_response.body).to include("오늘부터 시작!")
      expect(last_response.body).to include("연속 기록")
    end

    it "오늘 메모 2건 + 필기 1건 작성 후 → 오늘 카운트 = 3, 분해 표시" do
      post "/memos", body: "오늘 메모 1"
      post "/memos", body: "오늘 메모 2"
      post "/notes",
        "title" => "오늘 필기", "body" => "본문",
        "category" => "lessons", "source" => "교과서"

      get "/"
      expect(last_response.body).to match(/오늘.*?<span class="stats__value">3</m)
      expect(last_response.body).to include("💭 2")
      expect(last_response.body).to include("📝 1")
    end

    it "streak 1 — 오늘 메모 1건 작성 시" do
      post "/memos", body: "오늘 시작"
      get "/"
      expect(last_response.body).to match(/🔥 1/)
    end
  end

  describe "GapDetector 카드 (W17-T03)" do
    let(:db) { Sowing::Infrastructure::DB.connection }

    before do
      db[:entity_mentions].delete
      db[:entities].delete
    end

    after { Sowing::Infrastructure::Settings.update(class_roster: []) }

    it "학급 명단 미설정 시 — 안내 카드 (gap-card--prompt) 표시" do
      Sowing::Infrastructure::Settings.update(class_roster: [])
      get "/"
      expect(last_response.body).to include("학급 명단을 등록하면")
      expect(last_response.body).to include("gap-card--prompt")
    end

    it "전원 활성 — gap 카드 표시 안 함" do
      Sowing::Infrastructure::Settings.update(class_roster: %w[활성학생])
      db[:entities].insert(
        type: "student", name: "활성학생",
        first_seen_at: Time.now.iso8601, last_seen_at: Time.now.iso8601,
        mention_count: 1
      )
      get "/"
      expect(last_response.body).not_to include("지난 4주간 한 번도 등장 안 한 학생")
    end

    it "미언급 학생 있을 때 — gap 카드 + 학생 명단 표시" do
      Sowing::Infrastructure::Settings.update(class_roster: %w[민준 서연 지호])
      db[:entities].insert(
        type: "student", name: "민준",
        first_seen_at: Time.now.iso8601, last_seen_at: Time.now.iso8601,
        mention_count: 1
      )
      get "/"
      expect(last_response.body).to include("지난 4주간 한 번도 등장 안 한 학생")
      expect(last_response.body).to include("<strong>2명</strong>") # 서연, 지호
      expect(last_response.body).to include("서연")
      expect(last_response.body).to include("지호")
    end
  end

  describe "씨앗-숲 시각화 (W6-T03)" do
    let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }

    before do
      FileUtils.rm_rf(vault_dir.join("00_Inbox"))
      FileUtils.rm_rf(vault_dir.join("20_Notes"))
      FileUtils.rm_rf(vault_dir.join("30_Records"))
    end

    it "0건 — 시작 전 단계 표시 + SVG inline" do
      get "/"
      expect(last_response.body).to include("시작 전")
      expect(last_response.body).to include("<svg")
      expect(last_response.body).to include('class="growth"')
    end

    it "메모 1건 → 씨앗 단계 + 다음 단계까지 9건 안내" do
      post "/memos", body: "씨앗 1"
      get "/"
      expect(last_response.body).to include("씨앗")
      expect(last_response.body).to match(/다음 단계까지.*?<strong>9</)
    end

    it "외부 라이브러리 없이 inline SVG로만 렌더링 (CDN/img 불필요)" do
      get "/"
      growth_section = last_response.body[/<section class="growth"[\s\S]*?<\/section>/]
      expect(growth_section).to include("<svg")
      expect(growth_section).not_to include("<img")
      expect(growth_section).not_to include("https://")
    end

    it "progress bar 요소 포함" do
      get "/"
      expect(last_response.body).to include('<progress class="growth__progress"')
    end
  end

  describe "합성기 검토 위젯 (대시보드 → /synth 진입)" do
    let(:vault_synth_root) { Sowing::Infrastructure::Paths.vault_dir.join(".sowing/synth") }

    before do
      FileUtils.rm_rf(vault_synth_root)
    end

    it "합성 결과 0건 — 빈 상태 안내 + /synth 진입 링크" do
      get "/"
      expect(last_response).to be_ok
      expect(last_response.body).to include("합성기 검토")
      expect(last_response.body).to include("아직 합성 결과가 없어요")
      expect(last_response.body).to include('href="/synth"')
      expect(last_response.body).to include("synth-summary--empty")
    end

    it "type 별 합성 파일 시드 시 — chip 표시 + 카운트" do
      FileUtils.mkdir_p(vault_synth_root.join("students"))
      FileUtils.mkdir_p(vault_synth_root.join("reflections"))
      File.write(vault_synth_root.join("students/민준.md"), "---\nis_synth: true\n---\nx")
      File.write(vault_synth_root.join("students/서연.md"), "---\nis_synth: true\n---\nx")
      File.write(vault_synth_root.join("reflections/2026-1.md"), "---\nis_synth: true\n---\nx")

      get "/"
      expect(last_response.body).to include("검토 대기 중인 합성 결과")
      expect(last_response.body).to include("3건")
      expect(last_response.body).to include("학생 디제스트")
      expect(last_response.body).to include("학기 회고")
    end

    it "nav 에 /synth 진입 링크 존재" do
      get "/"
      expect(last_response.body).to include('href="/synth"')
      expect(last_response.body).to include("🌱 합성기")
    end
  end

  describe "이날의 회고 위젯 (30년 시나리오 #1)" do
    let(:db_inner) { Sowing::Infrastructure::DB.connection }
    let(:vault_dir_inner) { Sowing::Infrastructure::Paths.vault_dir }

    before do
      db_inner[:entries_fts].delete
      db_inner[:links].delete
      db_inner[:entry_tags].delete
      db_inner[:tags].delete
      db_inner[:entries].delete
      FileUtils.rm_rf(vault_dir_inner.join("00_Inbox"))
      FileUtils.rm_rf(vault_dir_inner.join("30_Records"))
    end

    def seed_today_past_year(years_ago:, title:, category: "수업회고")
      now = Time.now
      ts = Time.new(now.year - years_ago, now.month, now.day, 9, 0, 0, "+09:00")
      rid = "01OTD" + format("%021d", years_ago)
      path = "30_Records/#{ts.year}/#{category}/r-#{years_ago}.md"
      abs = vault_dir_inner.join(path)
      FileUtils.mkdir_p(abs.dirname)
      File.write(abs, "---\nid: #{rid}\nmode: record\ncategory: #{category}\ntitle: #{title}\ncreated_at: '#{ts.iso8601}'\nupdated_at: '#{ts.iso8601}'\n---\n\n본문\n")
      db_inner[:entries].insert(
        id: rid, path: path, mode: "record",
        category: category, title: title,
        created_at: ts.iso8601, updated_at: ts.iso8601,
        file_mtime: ts.to_i, file_hash: "0" * 16, word_count: 1, indexed_at: ts.iso8601
      )
    end

    it "과거 같은 날짜 entry 0건 — 빈 상태 placeholder 표시 (위젯 자체는 항상 노출, 30년 시나리오 인지)" do
      get "/"
      # 위젯 헤더는 항상 표시
      expect(last_response.body).to include("이날의 회고")
      # 빈 상태 안내
      expect(last_response.body).to include("30년 누적되면")
      expect(last_response.body).to include("on-this-day--empty")
    end

    it "과거 같은 날짜 entry 있을 때 — 위젯 표시 + 연도·제목 인용" do
      seed_today_past_year(years_ago: 1, title: "작년 같은 날 회고")
      seed_today_past_year(years_ago: 3, title: "3년 전 회고", category: "상담")
      get "/"
      expect(last_response.body).to include("이날의 회고")
      expect(last_response.body).to include("작년 같은 날 회고")
      expect(last_response.body).to include("3년 전 회고")
      expect(last_response.body).to match(/1년 전|3년 전/)
    end

    it "오늘과 같은 연도 entry 는 제외 (exclude_year)" do
      now = Time.now
      ts_today_this_year = Time.new(now.year, now.month, now.day, 9, 0, 0, "+09:00")
      rid = "01OTDTHISYEAR0000000000"
      path = "30_Records/#{ts_today_this_year.year}/today/now.md"
      abs = vault_dir_inner.join(path)
      FileUtils.mkdir_p(abs.dirname)
      File.write(abs, "---\nid: #{rid}\nmode: record\ncategory: today\ntitle: 오늘 작성된 것\ncreated_at: '#{ts_today_this_year.iso8601}'\nupdated_at: '#{ts_today_this_year.iso8601}'\n---\n\n본문\n")
      db_inner[:entries].insert(
        id: rid, path: path, mode: "record",
        category: "today", title: "오늘 작성된 것",
        created_at: ts_today_this_year.iso8601, updated_at: ts_today_this_year.iso8601,
        file_mtime: ts_today_this_year.to_i, file_hash: "0" * 16, word_count: 1, indexed_at: ts_today_this_year.iso8601
      )

      get "/"
      # 위젯에는 안 표시 (오늘 작성된 것 ≠ "이날의 회고")
      otd_section = last_response.body[/<aside class="on-this-day".*?<\/aside>/m]
      if otd_section
        expect(otd_section).not_to include("오늘 작성된 것")
      end
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
