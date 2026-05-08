# frozen_string_literal: true

require "sinatra/base"
require "commonmarker"

module Sowing
  module Controllers
    # 모든 컨트롤러의 부모. 공통 설정·헬퍼를 제공.
    # 실제 라우트는 자식 컨트롤러(DashboardController 등)가 정의하고,
    # config/routes.rb에서 Sowing::Application에 use 한다.
    class ApplicationController < Sinatra::Base
      set :root, Sowing.root
      set :views, File.join(Sowing.root, "views")
      set :public_folder, File.join(Sowing.root, "public")
      set :default_encoding, "utf-8"

      helpers do
        # 한국어 날짜 포맷: "2026년 5월 8일 금요일"
        def korean_today(time = Time.now)
          days = %w[일 월 화 수 목 금 토]
          "#{time.year}년 #{time.month}월 #{time.day}일 #{days[time.wday]}요일"
        end

        # 페이지 제목. view에서 `@page_title = "..."` 설정 가능.
        def page_title
          @page_title ? "#{@page_title} | Sowing" : "Sowing"
        end

        # 메모 카드 시간 라벨 — 오늘은 HH:MM, 어제는 "어제", 그 외는 M/D.
        def memo_time_label(time)
          today = Date.today
          date = time.to_date
          if date == today
            time.strftime("%H:%M")
          elsif date == today - 1
            "어제"
          else
            "#{date.month}/#{date.day}"
          end
        end

        # 본문 발췌 (한 줄, 길면 말줄임표).
        def memo_excerpt(body, limit = 80)
          stripped = body.to_s.strip
          (stripped.length > limit) ? "#{stripped[0, limit]}…" : stripped
        end

        # HTML escape — Sinatra의 escape_html은 sinatra/contrib에 있고 자식 컨트롤러에도 노출됨.
        # 본 헬퍼는 데모용 — 실제 ERB는 자동 escape를 위해 <%= h(...) %> 또는 erb -%> 사용.
        def h(text)
          Rack::Utils.escape_html(text.to_s)
        end

        # 옵시디언 호환 마크다운 → HTML.
        # - 헤더 앵커 비활성 (옵시디언 native 동작과 일치, 본문 깔끔)
        # - syntax highlighter 비활성 — 인라인 style 대신 우리 CSS로 통제
        # - render.unsafe: false — 사용자 입력의 raw <script> 차단 (CLAUDE.md 보안)
        # - 위키링크 [[link]]는 commonmarker가 처리하지 않음 → plain text. W3-T01에서 별도 파서.
        def markdown_to_html(text)
          Commonmarker.to_html(
            text.to_s,
            options: {
              extension: {header_ids: nil},
              render: {unsafe: false}
            },
            plugins: {syntax_highlighter: nil}
          )
        end
      end
    end
  end
end
