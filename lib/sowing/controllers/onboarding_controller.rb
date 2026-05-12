# frozen_string_literal: true

module Sowing
  module Controllers
    # 첫 실행 마법사 (W7-T01).
    #
    # 4단계 (welcome → vault → profile → samples) + done.
    # ApplicationController#before_filter에서 onboarding 미완료 시 자동 redirect.
    #
    # 각 단계는 GET(폼) + POST(저장) 페어. Settings.update로 진행 상태 누적.
    # 모두 완료하면 onboarding_completed: true 마킹 후 대시보드로.
    class OnboardingController < ApplicationController
      STEPS = %w[welcome vault profile samples done].freeze

      helpers do
        # Sinatra의 `settings` DSL과 이름 충돌 회피 — user_settings로 명명.
        def user_settings
          Core::Settings
        end

        def step_index(step)
          STEPS.index(step) || 0
        end
      end

      get "/onboarding" do
        redirect "/onboarding/welcome"
      end

      get "/onboarding/welcome" do
        @page_title = "환영합니다"
        @step = "welcome"
        @step_total = STEPS.size - 1 # done은 결과 화면이라 제외
        erb :"onboarding/welcome", layout: :"layouts/onboarding"
      end

      get "/onboarding/vault" do
        @page_title = "볼트 위치 확인"
        @step = "vault"
        @step_total = STEPS.size - 1
        @vault_dir = Core::Paths.vault_dir.to_s
        erb :"onboarding/vault", layout: :"layouts/onboarding"
      end

      post "/onboarding/vault" do
        user_settings.update(vault_consent: true)
        redirect "/onboarding/profile"
      end

      get "/onboarding/profile" do
        @page_title = "사용자 프로필"
        @step = "profile"
        @step_total = STEPS.size - 1
        @user_name = user_settings.load["user_name"]
        erb :"onboarding/profile", layout: :"layouts/onboarding"
      end

      post "/onboarding/profile" do
        name = params["user_name"].to_s.strip
        name = "선생님" if name.empty?
        user_settings.update(user_name: name)
        redirect "/onboarding/samples"
      end

      get "/onboarding/samples" do
        @page_title = "샘플 콘텐츠"
        @step = "samples"
        @step_total = STEPS.size - 1
        erb :"onboarding/samples", layout: :"layouts/onboarding"
      end

      post "/onboarding/samples" do
        consent = truthy?(params["sample_consent"])
        user_settings.update(
          sample_consent: consent,
          onboarding_completed: true,
          completed_at: Time.now.iso8601
        )
        # W7-T03: 동의 시 SeedSamples 즉시 실행. 중복 ULID는 Use Case가 자동 skip.
        @seed_summary = consent ? UseCases::SeedSamples.new.call.value_or({}) : {}
        # 결과는 session 또는 query로 전달 가능 — 단순화를 위해 session.
        session[:seed_summary] = @seed_summary
        redirect "/onboarding/done"
      end

      get "/onboarding/done" do
        @page_title = "준비 완료"
        @step = "done"
        @step_total = STEPS.size - 1
        @user_name = user_settings.load["user_name"]
        @sample_consent = user_settings.load["sample_consent"]
        @seed_summary = session.delete(:seed_summary) || {}
        erb :"onboarding/done", layout: :"layouts/onboarding"
      end

      private

      def truthy?(value)
        %w[1 true on yes].include?(value.to_s.downcase)
      end
    end
  end
end
