# frozen_string_literal: true

require "sinatra/base"

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
      end
    end
  end
end
