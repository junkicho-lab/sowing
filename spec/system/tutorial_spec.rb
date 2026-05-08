# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "튜토리얼 (W7-T04)", type: :request do
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
    %w[00_Inbox 20_Notes 30_Records].each { |d| FileUtils.rm_rf(vault_dir.join(d)) }
    Sowing::Infrastructure::Settings.update(
      onboarding_completed: true, tutorial_step: 1, tutorial_completed_at: nil
    )
  end

  describe "GET /tutorial" do
    it "기본 step 1 — 빠른 메모 안내" do
      get "/tutorial"
      expect(last_response).to be_ok
      expect(last_response.body).to include("1단계")
      expect(last_response.body).to match(/Cmd|⌘.*Shift.*M/)
    end

    it "메모가 1건 이상 있으면 step 2로 자동 진행" do
      post "/memos", body: "튜토리얼 진행용 메모"
      get "/tutorial"
      expect(last_response.body).to include("2단계")
    end

    it "memo + note가 있으면 step 3로" do
      post "/memos", body: "메모"
      post "/notes",
        "title" => "필기", "body" => "본문",
        "category" => "lessons", "source" => "교과서"
      get "/tutorial"
      expect(last_response.body).to include("3단계")
    end

    it "memo + note + record가 있으면 step 4 (완료 단계)로" do
      post "/memos", body: "메모"
      post "/notes",
        "title" => "필기", "body" => "본문",
        "category" => "lessons", "source" => "교과서"
      post "/records",
        "title" => "기록", "body" => "본문", "category" => "회고"
      get "/tutorial"
      expect(last_response.body).to include("4단계")
    end
  end

  describe "수동 진행 (POST /tutorial/next)" do
    it "step 1 → 2로 advance" do
      post "/tutorial/next"
      expect(Sowing::Infrastructure::Settings.load["tutorial_step"]).to eq(2)
    end

    it "step 4에서 next → tutorial_completed_at 마킹" do
      Sowing::Infrastructure::Settings.update(tutorial_step: 4)
      post "/tutorial/next"
      expect(Sowing::Infrastructure::Settings.load["tutorial_completed_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe "POST /tutorial/skip" do
    it "tutorial_completed_at 즉시 마킹 + 대시보드로 redirect" do
      post "/tutorial/skip"
      expect(Sowing::Infrastructure::Settings.load["tutorial_completed_at"]).not_to be_nil
      expect(last_response["Location"]).to end_with("/")
    end
  end

  describe "POST /tutorial/restart" do
    it "step 1로 리셋 + completed_at clear" do
      Sowing::Infrastructure::Settings.update(tutorial_step: 4, tutorial_completed_at: "2026-01-01T00:00:00+09:00")
      post "/tutorial/restart"
      settings = Sowing::Infrastructure::Settings.load
      expect(settings["tutorial_step"]).to eq(1)
      expect(settings["tutorial_completed_at"]).to be_nil
    end
  end

  describe "대시보드 통합" do
    it "tutorial 미완료 시 dashboard에 CTA 배너" do
      get "/"
      expect(last_response.body).to include("튜토리얼 시작")
    end

    it "tutorial 완료 후에는 CTA 안 보임" do
      Sowing::Infrastructure::Settings.update(tutorial_completed_at: "2026-05-09T10:00:00+09:00")
      get "/"
      expect(last_response.body).not_to include("3분짜리 인터랙티브 튜토리얼")
    end
  end

  describe "전체 흐름 (자동 감지로 4단계 모두)" do
    it "memo→note→record 작성으로 step 4까지 자동 진행" do
      get "/tutorial"
      expect(last_response.body).to include("1단계")

      post "/memos", body: "메모"
      get "/tutorial"
      expect(last_response.body).to include("2단계")

      post "/notes",
        "title" => "필기", "body" => "본문",
        "category" => "lessons", "source" => "교과서"
      get "/tutorial"
      expect(last_response.body).to include("3단계")

      post "/records",
        "title" => "기록", "body" => "본문", "category" => "회고"
      get "/tutorial"
      expect(last_response.body).to include("4단계")

      # 4단계에서 완료 버튼
      post "/tutorial/next"
      expect(Sowing::Infrastructure::Settings.load["tutorial_completed_at"]).not_to be_nil
    end
  end
end
