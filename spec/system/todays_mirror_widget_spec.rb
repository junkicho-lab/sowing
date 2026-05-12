# frozen_string_literal: true

require "rack/test"

# Phase 13 W28-T02 — 대시보드 '오늘의 자기' 위젯.
RSpec.describe "오늘의 자기 거울 위젯 (Phase 13 W28-T02)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:today_str) { Time.now.strftime("%Y-%m-%d") }
  let(:mirror_path) { vault_dir.join(".sowing/synth/self-mirror/daily-#{today_str}.md") }

  before do
    header "Host", "127.0.0.1"
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    %w[00_Inbox 20_Notes 30_Records .sowing/synth].each { |d| FileUtils.rm_rf(vault_dir.join(d)) }
    Sowing::Core::Settings.reset!
  end

  after { Sowing::Core::Settings.reset! }

  def setup_user
    Sowing::Core::Settings.save(
      "onboarding_completed" => true,
      "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00",
      "daily_mirror_enabled" => true
    )
  end

  def seed_today(count: 4)
    count.times do |i|
      Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "협동학습 잘됐 #{i}")
    end
  end

  describe "위젯 표시 조건" do
    it "옵션 꺼짐 → 위젯 안 표시" do
      Sowing::Core::Settings.save(
        "onboarding_completed" => true,
        "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00",
        "daily_mirror_enabled" => false
      )
      seed_today(count: 5)

      get "/"
      expect(last_response.body).not_to include("todays-mirror")
    end

    it "옵션 켜짐 + 오늘 entries < 3 → 위젯 안 표시" do
      setup_user
      seed_today(count: 2)

      get "/"
      expect(last_response.body).not_to include("todays-mirror")
    end

    it "옵션 켜짐 + 오늘 entries ≥ 3 + 미생성 → prompt 표시 (자동 생성 차단 시)" do
      # W28-T03 의 자동 생성 hook 이 prompt 상태를 즉시 ready 로 바꾸므로,
      # 자동 생성 실패 시나리오 (예: use case raise) 에만 prompt 도달 가능.
      # 이 spec 은 그 fallback 경로 검증.
      setup_user
      seed_today(count: 4)
      allow(Sowing::UseCases::SynthesizeSelfMirror).to receive(:new).and_raise(StandardError, "stub fail")

      get "/"
      expect(last_response.body).to include("todays-mirror--prompt")
      expect(last_response.body).to include("미생성")
      expect(last_response.body).to include("🌅 오늘 거울 만들기")
    end

    it "옵션 켜짐 + 오늘 mirror 생성됨 → ready 카드 + 5축 요약" do
      setup_user
      seed_today(count: 5)

      # mirror 생성 (결정적 모드)
      result = Sowing::UseCases::SynthesizeSelfMirror.new
        .call(period: :daily, date: today_str)
      expect(result.success?).to be true

      get "/"
      expect(last_response.body).to include("todays-mirror--ready")
      expect(last_response.body).to include("5축 자세히 보기")
      expect(last_response.body).to include("긍정")
      expect(last_response.body).to include("부정")
      expect(last_response.body).to include("deterministic")
    end

    it "ready 카드의 '자세히 보기' 링크가 /synth/self-mirror/daily-{today} 로" do
      setup_user
      seed_today(count: 5)
      Sowing::UseCases::SynthesizeSelfMirror.new.call(period: :daily, date: today_str)

      get "/"
      expect(last_response.body).to include(%(href="/synth/self-mirror/daily-#{today_str}))
    end
  end

  describe "prompt 의 form" do
    it "POST /synth/self-mirror/auto/generate (period=daily, date=오늘)" do
      setup_user
      seed_today(count: 4)
      # W28-T03 자동 생성 차단 — fallback 경로 검증
      allow(Sowing::UseCases::SynthesizeSelfMirror).to receive(:new).and_raise(StandardError, "stub fail")

      get "/"
      expect(last_response.body).to include('action="/synth/self-mirror/auto/generate"')
      expect(last_response.body).to include('name="period" value="daily"')
      expect(last_response.body).to include(%(name="date" value="#{today_str}"))
    end
  end

  describe "POST /settings/daily_mirror — 토글" do
    before do
      Sowing::Core::Settings.save(
        "onboarding_completed" => true,
        "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00"
      )
    end

    it "체크박스 ON → daily_mirror_enabled = true" do
      post "/settings/daily_mirror", daily_mirror_enabled: "1"
      expect(last_response.status).to eq(302)
      expect(Sowing::Core::Settings.load["daily_mirror_enabled"]).to be true
    end

    it "체크박스 OFF → daily_mirror_enabled = false" do
      Sowing::Core::Settings.update(daily_mirror_enabled: true)
      post "/settings/daily_mirror" # 체크박스 안 보냄
      expect(Sowing::Core::Settings.load["daily_mirror_enabled"]).to be false
    end

    it "flash 안내 표시" do
      post "/settings/daily_mirror", daily_mirror_enabled: "1"
      follow_redirect!
      expect(last_response.body).to include("활성화")
    end
  end

  describe "Settings UI" do
    it "설정 페이지에 자기 거울 섹션 + 체크박스 표시" do
      Sowing::Core::Settings.save(
        "onboarding_completed" => true,
        "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00"
      )

      get "/settings"
      expect(last_response.body).to include("🪞 자기 거울")
      expect(last_response.body).to include('name="daily_mirror_enabled"')
      expect(last_response.body).to include("W28-T03")  # cron 예정 안내
    end

    it "옵션 켜짐 시 체크박스 checked" do
      Sowing::Core::Settings.save(
        "onboarding_completed" => true,
        "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00",
        "daily_mirror_enabled" => true
      )

      get "/settings"
      expect(last_response.body).to match(%r{<input[^>]*name="daily_mirror_enabled"[^>]*checked})
    end
  end

  describe "graceful — Mirror 인프라 부재 시" do
    it "frontmatter 깨졌어도 위젯이 dashboard 부팅 막지 않음" do
      setup_user
      seed_today(count: 4)
      # 깨진 mirror 파일 쓰기
      FileUtils.mkdir_p(mirror_path.dirname)
      File.write(mirror_path, "completely broken yaml ::: -")

      get "/"
      expect(last_response.status).to eq(200) # dashboard 정상 응답
    end
  end
end
