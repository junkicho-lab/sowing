# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "설정 화면 (W7-T06)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }

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
    %w[00_Inbox 20_Notes 30_Records .sowing/trash].each { |d| FileUtils.rm_rf(vault_dir.join(d)) }
    Sowing::Core::Settings.update(
      onboarding_completed: true, user_name: nil,
      tutorial_completed_at: nil, tutorial_step: 1
    )
  end

  describe "GET /settings" do
    before { get "/settings" }

    it "200 OK + 모든 핵심 섹션 표시" do
      expect(last_response).to be_ok
      %w[프로필 데이터\ 위치 단축키 동기화 학습 샘플].each { |kw| expect(last_response.body).to include(kw) }
    end

    it "현재 볼트·데이터 경로 안내" do
      expect(last_response.body).to include(vault_dir.to_s)
    end

    it "헤더 nav에 /settings 링크 (Phase 13 IA — 직접 1급)" do
      get "/"
      expect(last_response.body).to include('href="/settings"')
    end
  end

  describe "POST /settings/profile" do
    it "이름 저장 + flash 메시지" do
      post "/settings/profile", "user_name" => "이선생"
      expect(Sowing::Core::Settings.load["user_name"]).to eq("이선생")

      follow_redirect!
      expect(last_response.body).to include("프로필을 저장했습니다")
    end

    it "빈 입력 → user_name 제거 (nil)" do
      Sowing::Core::Settings.update(user_name: "기존")
      post "/settings/profile", "user_name" => "  "
      expect(Sowing::Core::Settings.load["user_name"]).to be_nil
    end
  end

  describe "POST /settings/class_roster (W17-T03)" do
    after { Sowing::Core::Settings.update(class_roster: []) }

    it "줄바꿈 구분 명단 저장" do
      post "/settings/class_roster", "class_roster" => "민준\n서연\n지호"
      expect(Sowing::Core::Settings.load["class_roster"]).to eq(%w[민준 서연 지호])
      follow_redirect!
      expect(last_response.body).to include("3명을 저장했습니다")
    end

    it "쉼표 구분도 허용" do
      post "/settings/class_roster", "class_roster" => "민준, 서연, 지호"
      expect(Sowing::Core::Settings.load["class_roster"]).to eq(%w[민준 서연 지호])
    end

    it "중복·공백 제거" do
      post "/settings/class_roster", "class_roster" => "민준\n  \n민준\n서연\n"
      expect(Sowing::Core::Settings.load["class_roster"]).to eq(%w[민준 서연])
    end

    it "settings 화면에 명단 입력 textarea 표시" do
      Sowing::Core::Settings.update(class_roster: %w[민준 서연])
      get "/settings"
      expect(last_response.body).to include('name="class_roster"')
      expect(last_response.body).to include("민준\n서연") # textarea pre-filled
      expect(last_response.body).to include("현재")
      expect(last_response.body).to include("2명")
    end
  end

  describe "POST /settings/samples/delete" do
    it "샘플 시드된 상태에서 호출 → 12건 휴지통 + flash" do
      Sowing::UseCases::SeedSamples.new.call
      expect(db[:entries].count).to eq(12)

      post "/settings/samples/delete"
      expect(db[:entries].count).to eq(0)

      follow_redirect!
      expect(last_response.body).to include("샘플 12건")
    end

    it "샘플 없으면 'No samples' 안내" do
      post "/settings/samples/delete"
      follow_redirect!
      expect(last_response.body).to include("삭제할 샘플이 없습니다")
    end
  end

  describe "POST /settings/restart_onboarding" do
    it "onboarding_completed false + tutorial 리셋 + 마법사로 redirect" do
      Sowing::Core::Settings.update(tutorial_completed_at: "2026-05-09T10:00:00+09:00")
      post "/settings/restart_onboarding"

      settings = Sowing::Core::Settings.load
      expect(settings["onboarding_completed"]).to be false
      expect(settings["tutorial_completed_at"]).to be_nil
      expect(last_response["Location"]).to end_with("/onboarding/welcome")
    end
  end

  describe "POST /settings/restart_tutorial" do
    it "tutorial 리셋 + tutorial 페이지로" do
      Sowing::Core::Settings.update(tutorial_step: 4, tutorial_completed_at: "2026-05-09T10:00:00+09:00")
      post "/settings/restart_tutorial"

      settings = Sowing::Core::Settings.load
      expect(settings["tutorial_step"]).to eq(1)
      expect(settings["tutorial_completed_at"]).to be_nil
      expect(last_response["Location"]).to end_with("/tutorial")
    end
  end
end
