# frozen_string_literal: true

module Sowing
  module Controllers
    # 대시보드(홈). 사용자가 진입하는 첫 화면.
    # SPEC §10.3 와이어프레임 참조 — W2-T01에서는 빈 화면 + 다음 행동 CTA만.
    class DashboardController < ApplicationController
      get "/" do
        @page_title = "대시보드"
        erb :"dashboard/show", layout: :"layouts/application"
      end
    end
  end
end
