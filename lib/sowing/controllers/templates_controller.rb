# frozen_string_literal: true

module Sowing
  module Controllers
    # 템플릿 관리 (W6-T04). vault/templates/ 마크다운 SoT.
    #
    # GET  /templates           — 목록
    # GET  /templates/new       — 신규 폼
    # POST /templates           — 저장 (슬러그 + 본문)
    # GET  /templates/:slug     — 미리보기 (default_context 치환 결과)
    class TemplatesController < ApplicationController
      ERROR_MESSAGES = {
        empty_slug: "템플릿 이름을 입력해 주세요.",
        invalid_slug: "이름은 한글/영문/숫자/하이픈/언더스코어만 가능합니다 (최대 80자).",
        empty_content: "본문을 입력해 주세요."
      }.freeze

      helpers do
        def template_repo
          @template_repo ||= Repositories::TemplateRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        end

        def template_error_message(failure)
          ERROR_MESSAGES.fetch(failure, "저장 실패: #{failure}")
        end
      end

      get "/templates" do
        @page_title = "템플릿"
        @templates = template_repo.list
        erb :"templates/index", layout: :"layouts/application"
      end

      get "/templates/new" do
        @page_title = "새 템플릿"
        @form = {slug: nil, content: ""}
        @error = nil
        erb :"templates/new", layout: :"layouts/application"
      end

      post "/templates" do
        slug = params["slug"].to_s.strip
        content = params["content"].to_s

        failure = validate_input(slug, content)
        if failure
          @page_title = "새 템플릿"
          @form = {slug: slug, content: content}
          @error = template_error_message(failure)
          status 422
          halt erb(:"templates/new", layout: :"layouts/application")
        end

        begin
          template = template_repo.save(slug: slug, content: content)
          redirect "/templates/#{Rack::Utils.escape(template.slug)}"
        rescue ArgumentError
          @page_title = "새 템플릿"
          @form = {slug: slug, content: content}
          @error = template_error_message(:invalid_slug)
          status 422
          erb :"templates/new", layout: :"layouts/application"
        end
      end

      get "/templates/:slug" do
        @template = template_repo.find(params["slug"])
        if @template.nil?
          status 404
          @page_title = "찾을 수 없음"
          @message = "템플릿을 찾을 수 없습니다."
          halt erb(:"errors/404", layout: :"layouts/application")
        end

        @page_title = @template.name
        @rendered = template_repo.render(@template.content)
        erb :"templates/show", layout: :"layouts/application"
      end

      private

      def validate_input(slug, content)
        return :empty_slug if slug.empty?
        return :empty_content if content.strip.empty?
        nil
      end
    end
  end
end
