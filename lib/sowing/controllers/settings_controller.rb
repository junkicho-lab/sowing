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
          Core::Settings
        end

        def settings_index_repo
          @settings_index_repo ||= Repositories::IndexRepo.new
        end
      end

      get "/settings" do
        @page_title = "설정"
        @settings_data = user_settings.load
        @vault_dir = Core::Paths.vault_dir
        @data_dir = Core::Paths.data_dir
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

      post "/settings/class_roster" do
        # 한 줄당 한 명. 줄바꿈/쉼표 모두 허용.
        raw = params["class_roster"].to_s
        roster = raw.split(/[\n,]/).map(&:strip).reject(&:empty?).uniq
        user_settings.update(class_roster: roster)
        session[:flash] = "학급 명단 #{roster.size}명을 저장했습니다."
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

      # Phase 13 W28-T02 — 자기 거울 위젯 활성화 토글.
      # 체크박스 켜면 'daily_mirror_enabled' = true, 끄면 false.
      post "/settings/daily_mirror" do
        enabled = params["daily_mirror_enabled"].to_s == "1"
        user_settings.update(daily_mirror_enabled: enabled)
        session[:flash] = enabled ? "🪞 자기 거울 위젯이 활성화됐습니다." : "자기 거울 위젯이 비활성화됐습니다."
        redirect "/settings"
      end

      # Phase 14 W29 PoC — 다크 모드 테마 토글.
      # theme = auto|light|dark (allowlist, 그 외는 auto 폴백).
      post "/settings/theme" do
        theme = params["theme"].to_s
        theme = "auto" unless %w[auto light dark].include?(theme)
        user_settings.update(theme: theme)
        session[:flash] = case theme
                         when "auto"  then "🌗 테마: 시스템 자동 (OS 따라감)"
                         when "light" then "☀ 테마: 라이트 모드"
                         when "dark"  then "🌑 테마: 다크 모드"
                         end
        redirect "/settings"
      end

      # Phase 14 W30 PoC — 단축키 사용자 정의.
      # modifier (Cmd/Ctrl+Shift) 고정, 한 글자만 변경 가능.
      # 안전한 charset (a-z) 만 허용 — modifier 충돌·브라우저 충돌 회피.
      post "/settings/shortcuts" do
        memo_key = sanitize_shortcut_key(params["shortcut_quick_memo"], default: "m")
        search_key = sanitize_shortcut_key(params["shortcut_quick_search"], default: "k")
        user_settings.update(
          shortcut_quick_memo: memo_key,
          shortcut_quick_search: search_key
        )
        session[:flash] = "⌨ 단축키 저장: ⌘⇧#{memo_key.upcase} (빠른 메모), ⌘#{search_key.upcase} (빠른 검색)"
        redirect "/settings"
      end

      helpers do
        # 단일 영문 소문자 1글자만 허용 — 그 외 (특수문자·숫자·다국어) 는 default
        def sanitize_shortcut_key(raw, default:)
          s = raw.to_s.strip.downcase
          s.match?(/\A[a-z]\z/) ? s : default
        end
      end

      # Phase 13 W25-T02 — 동사 중심 nav 변경 안내 모달 닫기.
      # AJAX POST (fetch) — JS 가 모달 hide 후 200 OK 받으면 종료.
      # form fallback (HTML POST) 도 작동 — JS 비활성화 시 redirect.
      # 분기: X-Requested-With: XMLHttpRequest (명시 AJAX) 또는 Accept 가
      # 정확히 application/json 인 경우만 JSON. 그 외는 redirect (form fallback).
      post "/settings/dismiss-ia-v2" do
        user_settings.update(ia_v2_seen_at: Time.now.iso8601)
        accept = request.env["HTTP_ACCEPT"].to_s
        if request.xhr? || accept.include?("application/json") && !accept.start_with?("*/*")
          content_type :json
          {status: "ok"}.to_json
        else
          redirect back || "/"
        end
      end
    end
  end
end
