# frozen_string_literal: true

module Sowing
  module Controllers
    # 필기(Note) — 외부 자료 정리·요약 (책·연수·수업·회의).
    # W2-T04/1: index + new + create.
    # 추후 W2-T04/2 (show), W2-T04/3 (edit + update) 예정.
    class NotesController < ApplicationController
      CATEGORIES = {
        "lessons" => "수업",
        "trainings" => "연수",
        "books" => "도서",
        "meetings" => "회의"
      }.freeze
      PER_PAGE = 30
      MAX_PAGE = 10_000

      ERROR_MESSAGES = {
        empty_title: "제목을 입력해 주세요.",
        empty_body: "본문을 입력해 주세요.",
        empty_category: "카테고리를 선택해 주세요.",
        invalid_category: "유효하지 않은 카테고리입니다.",
        empty_source: "출처를 입력해 주세요."
      }.freeze

      helpers do
        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        end

        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        def create_note_use_case
          UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def categories
          CATEGORIES
        end

        def category_label(key)
          CATEGORIES[key] || key
        end

        def parse_tags(raw)
          raw.to_s.split(/[\s,]+/).reject(&:empty?)
        end

        def error_message(failure)
          ERROR_MESSAGES.fetch(failure, "저장 실패: #{failure}")
        end

        def load_note_page(page:, per_page:, category: nil)
          offset = (page - 1) * per_page
          index_repo.list(mode: :note, category: category, limit: per_page, offset: offset).filter_map do |indexed|
            vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            nil
          end
        end
      end

      get "/notes" do
        @page_title = "필기"
        @page = (params["page"] || 1).to_i.clamp(1, MAX_PAGE)
        @per_page = PER_PAGE
        @category = params["category"].to_s.empty? ? nil : params["category"]
        @category = nil unless @category.nil? || CATEGORIES.key?(@category)
        @total = index_repo.count(mode: :note, category: @category)
        @total_pages = [(@total / @per_page.to_f).ceil, 1].max
        @notes = load_note_page(page: @page, per_page: @per_page, category: @category)
        erb :"notes/index", layout: :"layouts/application"
      end

      get "/notes/new" do
        @page_title = "필기 작성"
        @form = empty_form
        @error = nil
        erb :"notes/new", layout: :"layouts/application"
      end

      post "/notes" do
        result = create_note_use_case.call(
          title: params["title"].to_s,
          body: params["body"].to_s,
          category: params["category"].to_s,
          source: params["source"].to_s,
          tags: parse_tags(params["tags"])
        )

        if result.success?
          redirect "/notes"
        else
          @page_title = "필기 작성"
          @form = {
            title: params["title"],
            body: params["body"],
            category: params["category"],
            source: params["source"],
            tags: params["tags"]
          }
          @error = error_message(result.failure)
          status 422
          erb :"notes/new", layout: :"layouts/application"
        end
      end

      private

      def empty_form
        {title: nil, body: nil, category: nil, source: nil, tags: nil}
      end
    end
  end
end
