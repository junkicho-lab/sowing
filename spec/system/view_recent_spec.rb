# frozen_string_literal: true

require "rack/test"

# Phase 13 W26-T03 — '쓴 글 보기' 통합 시간순 (/view/recent).
# 메모·필기·기록 mode 무관 시간순 — 사용자 의도 ("최근 뭐 적었지") 1:1 매핑.
RSpec.describe "쓴 글 보기 — 통합 시간순 (Phase 13 W26-T03)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }

  before do
    header "Host", "127.0.0.1"
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    %w[00_Inbox 20_Notes 30_Records].each { |d| FileUtils.rm_rf(vault_dir.join(d)) }
  end

  # 3 mode 시드 — 시간 간격 두고 생성
  def seed_three_modes
    Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
      .call(body: "오늘 협동학습 메모 #회고")
    sleep 0.01
    Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo)
      .call(title: "수업 설계", body: "협동학습 본격 도입", category: "lessons", source: "필기")
    sleep 0.01
    Sowing::UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo)
      .call(title: "5월 회고", body: "이번 주 정리", category: "수업회고")
  end

  describe "GET /view → redirect /view/recent" do
    it "기본 라우트가 /view/recent 로 redirect" do
      get "/view"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/view/recent")
    end
  end

  describe "GET /view/recent — 통합 시간순" do
    it "빈 vault → empty state 표시" do
      get "/view/recent"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("entries 가 없습니다")
    end

    it "3 mode 모두 시간순 노출 (가장 늦은 record 가 첫 번째)" do
      seed_three_modes
      get "/view/recent"
      expect(last_response.status).to eq(200)

      body = last_response.body
      record_idx = body.index("5월 회고")
      note_idx = body.index("수업 설계")
      memo_idx = body.index("협동학습 메모")

      expect(record_idx).not_to be_nil
      expect(note_idx).not_to be_nil
      expect(memo_idx).not_to be_nil
      # 시간순 — 늦게 만든 게 위에
      expect(record_idx).to be < note_idx
      expect(note_idx).to be < memo_idx
    end

    it "각 mode 별 뱃지 표시 (💭 메모 / 📝 필기 / 📖 기록)" do
      seed_three_modes
      get "/view/recent"
      expect(last_response.body).to include("💭 메모")
      expect(last_response.body).to include("📝 필기")
      expect(last_response.body).to include("📖 기록")
    end

    it "각 entry 가 mode 별 detail 페이지로 링크" do
      seed_three_modes
      get "/view/recent"
      expect(last_response.body).to match(%r{href="/memos/[0-9A-Z]{26}"})
      expect(last_response.body).to match(%r{href="/notes/[0-9A-Z]{26}"})
      expect(last_response.body).to match(%r{href="/records/[0-9A-Z]{26}"})
    end
  end

  describe "필터 — mode chip" do
    before { seed_three_modes }

    it "?mode=memo → 메모만" do
      get "/view/recent?mode=memo"
      expect(last_response.body).to include("협동학습 메모")
      expect(last_response.body).not_to include("5월 회고")
      expect(last_response.body).not_to include("수업 설계")
    end

    it "?mode=note → 필기만" do
      get "/view/recent?mode=note"
      expect(last_response.body).to include("수업 설계")
      expect(last_response.body).not_to include("협동학습 메모")
    end

    it "?mode=record → 기록만" do
      get "/view/recent?mode=record"
      expect(last_response.body).to include("5월 회고")
      expect(last_response.body).not_to include("수업 설계")
    end

    it "잘못된 mode → 무시, 전체 표시" do
      get "/view/recent?mode=evil"
      expect(last_response.body).to include("5월 회고")
      expect(last_response.body).to include("수업 설계")
      expect(last_response.body).to include("협동학습 메모")
    end
  end

  describe "필터 — 카테고리 chip" do
    before { seed_three_modes }

    it "?category=수업회고 → 해당 카테고리만" do
      get "/view/recent?category=#{Rack::Utils.escape('수업회고')}"
      expect(last_response.body).to include("5월 회고")
      expect(last_response.body).not_to include("수업 설계") # 카테고리=lessons
    end

    it "카테고리 chip 이 동적으로 노출 (현재 vault 데이터 기반)" do
      get "/view/recent"
      expect(last_response.body).to include("lessons")
      expect(last_response.body).to include("수업회고")
    end
  end

  describe "limit 페이징" do
    before do
      # 15건 메모 시드
      15.times do |i|
        Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
          .call(body: "메모 #{i}")
        sleep 0.01
      end
    end

    it "?limit=5 → 5건만" do
      get "/view/recent?limit=5"
      # 본문에 'memo' badge 가 5번 (li 안의 badge 만 카운트)
      badge_count = last_response.body.scan(/view-recent__badge--memo/).size
      expect(badge_count).to eq(5)
    end

    it "limit 미지정 → 기본 100 (실 데이터 15건 모두)" do
      get "/view/recent"
      badge_count = last_response.body.scan(/view-recent__badge--memo/).size
      expect(badge_count).to eq(15)
    end

    it "limit > MAX (300) → 클램프" do
      get "/view/recent?limit=9999"
      # 실 데이터 15건만 — 클램프 자체는 controller 안에서 검증
      badge_count = last_response.body.scan(/view-recent__badge--memo/).size
      expect(badge_count).to eq(15)
    end

    it "음수 limit → 기본값 100" do
      get "/view/recent?limit=-5"
      expect(last_response.status).to eq(200)
    end
  end

  describe "nav 통합" do
    it "'쓴 글 보기' dropdown 에 /view/recent 진입점" do
      get "/"
      expect(last_response.body).to include('href="/view/recent"')
      expect(last_response.body).to include("🕐 최근 (통합 시간순)")
    end
  end
end
