# frozen_string_literal: true

module Sowing
  module Controllers
    # 마크다운 라이브 프리뷰. mode-agnostic — 본문(body)만 받아 HTML로 렌더해 Turbo Stream으로 회신.
    # 서버측 commonmarker가 단일 진실 렌더링 (옵시디언 호환성·SoT 원칙 일관).
    class PreviewController < ApplicationController
      TURBO_STREAM_TYPE = "text/vnd.turbo-stream.html"

      post "/preview" do
        content_type TURBO_STREAM_TYPE
        @rendered_html = markdown_to_html(params["body"].to_s)
        erb :"preview/_response.turbo_stream", layout: false
      end
    end
  end
end
