# frozen_string_literal: true

module Sowing
  module Controllers
    # 첫 메모 인터랙티브 튜토리얼 (W7-T04).
    #
    # 4단계 학습:
    #   1. 메모 — 빠른 메모로 한 줄 남기기 (Cmd/Ctrl+Shift+M 시연)
    #   2. 필기 승격 — 메모 → 필기로 정리 (카테고리·태그·제목)
    #   3. 기록 승격 — 필기·메모 → 기록으로 영구 보관
    #   4. 완료 — 다음 단계(검색·통계 등) 안내
    #
    # 진행 상태: Settings.tutorial_step (1~4) + tutorial_completed_at.
    # 자동 감지: IndexRepo 카운트로 각 단계의 "해봤음"을 추론 — 사용자가
    # "Done"을 누르지 않아도 실행 결과가 있으면 완료로 간주.
    class TutorialController < ApplicationController
      STEP_TOTAL = 4

      helpers do
        def user_settings
          Infrastructure::Settings
        end

        def tutorial_index_repo
          @tutorial_index_repo ||= Repositories::IndexRepo.new
        end

        # 자동 감지: 해당 mode entry가 1건 이상 있으면 그 단계는 "해본 것"으로 간주.
        # 샘플 시드를 받은 경우 이미 완료된 상태에서 시작 가능.
        def tutorial_step_done?(step)
          case step
          when 1 then tutorial_index_repo.count(mode: :memo) > 0
          when 2 then tutorial_index_repo.count(mode: :note) > 0
          when 3 then tutorial_index_repo.count(mode: :record) > 0
          else false
          end
        end
      end

      get "/tutorial" do
        @page_title = "첫 메모 튜토리얼"
        # 자동 진행: 현재 step이 자동 감지로 완료되어 있으면 다음으로 점프.
        saved_step = user_settings.load["tutorial_step"].to_i.clamp(1, STEP_TOTAL)
        auto_advanced_to = saved_step
        while auto_advanced_to < STEP_TOTAL && tutorial_step_done?(auto_advanced_to)
          auto_advanced_to += 1
        end
        # saved_step 이 자동 진행됐으면 settings 에도 저장 (재진입 시 일관성).
        user_settings.update(tutorial_step: auto_advanced_to) if auto_advanced_to != saved_step

        # 사용자가 ?step=N 으로 임의 단계 점프 가능 — 자동 진행으로 1~3 단계가
        # 건너뛰어졌어도 progress nav 클릭으로 다시 볼 수 있음.
        requested = params["step"].to_i
        @step =
          if requested.between?(1, STEP_TOTAL)
            requested
          else
            auto_advanced_to
          end
        # auto-jump 가 일어났다면 view 에 안내용 컨텍스트 제공
        @auto_jumped = (auto_advanced_to > saved_step) && requested.zero?
        @auto_advanced_to = auto_advanced_to

        @step_total = STEP_TOTAL
        @counts = {
          memo: tutorial_index_repo.count(mode: :memo),
          note: tutorial_index_repo.count(mode: :note),
          record: tutorial_index_repo.count(mode: :record)
        }
        @completed_at = user_settings.load["tutorial_completed_at"]
        erb :"tutorial/index", layout: :"layouts/application"
      end

      post "/tutorial/next" do
        current = user_settings.load["tutorial_step"].to_i
        next_step = (current + 1).clamp(1, STEP_TOTAL)
        if next_step >= STEP_TOTAL
          user_settings.update(tutorial_step: STEP_TOTAL, tutorial_completed_at: Time.now.iso8601)
        else
          user_settings.update(tutorial_step: next_step)
        end
        redirect "/tutorial"
      end

      post "/tutorial/skip" do
        user_settings.update(tutorial_step: STEP_TOTAL, tutorial_completed_at: Time.now.iso8601)
        redirect "/"
      end

      post "/tutorial/restart" do
        user_settings.update(tutorial_step: 1, tutorial_completed_at: nil)
        redirect "/tutorial"
      end
    end
  end
end
