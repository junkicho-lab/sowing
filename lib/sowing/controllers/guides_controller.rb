# frozen_string_literal: true

module Sowing
  module Controllers
    # 클라우드 동기화 가이드 표시 (W7-T05).
    #
    # `templates/guides/*.md` 를 마크다운 → HTML 렌더해 보여준다.
    # 시스템 제공 정적 콘텐츠라 사용자 정의·편집 UI는 두지 않음.
    class GuidesController < ApplicationController
      GUIDES_DIR = File.expand_path("../../../templates/guides", __dir__)

      # ROADMAP 4종 + 표시 순서 보존용 메타. 파일명에 매핑.
      GUIDES = [
        {slug: "sync_icloud", label: "iCloud Drive", icon: "☁️", os: "macOS·iOS"},
        {slug: "sync_onedrive", label: "OneDrive", icon: "📦", os: "Windows·macOS·Linux(rclone)"},
        {slug: "sync_dropbox", label: "Dropbox", icon: "🗂️", os: "macOS·Windows·Linux"},
        {slug: "sync_syncthing", label: "Syncthing (P2P)", icon: "🔗", os: "macOS·Windows·Linux·Android"}
      ].freeze

      helpers do
        def guide_path(slug)
          File.join(GUIDES_DIR, "#{slug}.md")
        end

        def guide_meta(slug)
          GUIDES.find { |g| g[:slug] == slug }
        end
      end

      get "/guides" do
        @page_title = "동기화 가이드"
        @guides = GUIDES
        erb :"guides/index", layout: :"layouts/application"
      end

      get "/guides/:slug" do
        meta = guide_meta(params["slug"])
        path = guide_path(params["slug"])
        if meta.nil? || !File.exist?(path)
          status 404
          @page_title = "찾을 수 없음"
          @message = "가이드를 찾을 수 없습니다."
          halt erb(:"errors/404", layout: :"layouts/application")
        end

        @guide = meta
        @body_html = markdown_to_html(File.read(path))
        @page_title = meta[:label]
        erb :"guides/show", layout: :"layouts/application"
      end
    end
  end
end
