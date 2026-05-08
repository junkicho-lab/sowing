# frozen_string_literal: true

module Sowing
  module Controllers
    # 설정 화면 (W7-T06).
    #
    # 표시 / 변경 가능 항목:
    #   - 사용자 프로필 (이름) — 인라인 편집
    #   - 볼트 위치 — 환경 변수 안내 (런타임 변경 불가, 재시작 필요)
    #   - 단축키 — 표시 (현재 고정)
    #   - 동기화·튜토리얼 진입점
    #   - 샘플 일괄 삭제
    #   - 온보딩 다시 보기 (재실행)
    class SettingsController < ApplicationController
      helpers do
        def user_settings
          Infrastructure::Settings
        end

        def settings_index_repo
          @settings_index_repo ||= Repositories::IndexRepo.new
        end
      end

      get "/settings" do
        @page_title = "설정"
        @settings_data = user_settings.load
        @vault_dir = Infrastructure::Paths.vault_dir
        @data_dir = Infrastructure::Paths.data_dir
        @samples = settings_index_repo.find_samples
        @flash = session.delete(:flash)
        erb :"settings/index", layout: :"layouts/application"
      end

      post "/settings/profile" do
        name = params["user_name"].to_s.strip
        user_settings.update(user_name: name.empty? ? nil : name)
        session[:flash] = "프로필을 저장했습니다."
        redirect "/settings"
      end

      post "/settings/samples/delete" do
        result = UseCases::DeleteSamples.new.call
        count = result.value_or(0)
        session[:flash] = (count > 0) ? "샘플 #{count}건을 휴지통으로 이동했습니다." : "삭제할 샘플이 없습니다."
        redirect "/settings"
      end

      post "/settings/restart_onboarding" do
        user_settings.update(
          onboarding_completed: false,
          tutorial_step: 1,
          tutorial_completed_at: nil
        )
        redirect "/onboarding/welcome"
      end

      post "/settings/restart_tutorial" do
        user_settings.update(tutorial_step: 1, tutorial_completed_at: nil)
        redirect "/tutorial"
      end
    end
  end
end
