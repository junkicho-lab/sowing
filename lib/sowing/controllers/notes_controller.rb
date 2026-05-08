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
        empty_category: "카테고리를 입력해 주세요.",
        invalid_category: "유효하지 않은 카테고리입니다.",
        empty_source: "출처를 입력해 주세요.",
        not_found: "필기를 찾을 수 없습니다.",
        not_promotable: "이 항목은 승격 대상이 아닙니다.",
        file_missing: "필기 파일이 존재하지 않습니다."
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

        def update_note_use_case
          UseCases::UpdateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def promote_to_record_use_case
          UseCases::PromoteToRecord.new(vault_repo: vault_repo, index_repo: index_repo)
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

        # id로 Note를 찾는다. 없거나 mode 불일치/파일 누락이면 nil.
        def find_note(id)
          indexed = index_repo.find(id)
          return nil if indexed.nil? || indexed.mode != :note
          vault_repo.read(indexed.path)
        rescue Errno::ENOENT
          nil
        end

        # Note → 폼 상태 Hash (edit 페이지 prefill에 사용).
        def note_to_form(note)
          {
            title: note.title,
            body: note.body,
            category: note.category,
            source: note.source,
            tags: note.tags.to_a.join(", ")
          }
        end

        def halt_with_404(message)
          status 404
          @page_title = "찾을 수 없음"
          @message = message
          halt erb(:"errors/404", layout: :"layouts/application")
        end

        def conflict?(result)
          result.failure? && result.failure.is_a?(Array) && result.failure.first == :conflict
        end

        def truthy?(value)
          %w[1 true on yes].include?(value.to_s.downcase)
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

      get "/notes/:id" do
        @note = find_note(params["id"])
        halt_with_404("필기를 찾을 수 없습니다.") if @note.nil?

        @page_title = @note.title
        erb :"notes/show", layout: :"layouts/application"
      end

      get "/notes/:id/edit" do
        @note = find_note(params["id"])
        halt_with_404("필기를 찾을 수 없습니다.") if @note.nil?

        @page_title = "필기 편집"
        @form = note_to_form(@note)
        @expected_file_hash = vault_repo.file_hash(index_repo.find(@note.id).path)
        @error = nil
        erb :"notes/edit", layout: :"layouts/application"
      end

      patch "/notes/:id" do
        force = truthy?(params["force"])
        result = update_note_use_case.call(
          id: params["id"],
          title: params["title"].to_s,
          body: params["body"].to_s,
          category: params["category"].to_s,
          source: params["source"].to_s,
          tags: parse_tags(params["tags"]),
          expected_file_hash: params["expected_file_hash"],
          force: force
        )

        if result.success?
          redirect "/notes/#{result.value!.id}"
        elsif conflict?(result)
          @note = find_note(params["id"])
          @page_title = "충돌 감지"
          @conflict = result.failure[1]
          @kind = :note
          status 409
          erb :"shared/_conflict", layout: :"layouts/application"
        elsif [:not_found, :file_missing].include?(result.failure)
          halt_with_404("필기를 찾을 수 없습니다.")
        else
          @note = find_note(params["id"])
          @page_title = "필기 편집"
          @form = {
            title: params["title"],
            body: params["body"],
            category: params["category"],
            source: params["source"],
            tags: params["tags"]
          }
          @expected_file_hash = params["expected_file_hash"]
          @error = error_message(result.failure)
          status 422
          erb :"notes/edit", layout: :"layouts/application"
        end
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

      get "/notes/:id/promote_to_record" do
        @note = find_note(params["id"])
        halt_with_404(ERROR_MESSAGES[:not_found]) if @note.nil?

        @page_title = "기록으로 승격"
        @form = {
          title: @note.title, # note title prefill — 사용자 편집 가능
          category: nil,
          tags: @note.tags.to_a.join(", ")
        }
        @categories = index_repo.distinct_categories(mode: :record)
        @error = nil
        erb :"notes/promote_to_record", layout: :"layouts/application"
      end

      post "/notes/:id/promote_to_record" do
        result = promote_to_record_use_case.call(
          id: params["id"],
          title: params["title"].to_s,
          category: params["category"].to_s,
          tags: parse_tags(params["tags"])
        )

        if result.success?
          redirect "/records/#{result.value!.id}"
        elsif [:not_found, :not_promotable, :file_missing].include?(result.failure)
          halt_with_404(error_message(result.failure))
        else
          @note = find_note(params["id"]) || halt_with_404(ERROR_MESSAGES[:not_found])
          @page_title = "기록으로 승격"
          @form = {
            title: params["title"],
            category: params["category"],
            tags: params["tags"]
          }
          @categories = index_repo.distinct_categories(mode: :record)
          @error = error_message(result.failure)
          status 422
          erb :"notes/promote_to_record", layout: :"layouts/application"
        end
      end

      private

      def empty_form
        {title: nil, body: nil, category: nil, source: nil, tags: nil}
      end
    end
  end
end
