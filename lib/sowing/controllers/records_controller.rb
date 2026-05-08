# frozen_string_literal: true

module Sowing
  module Controllers
    # 기록(Record) — 자기 경험·통찰의 영구 보관.
    # 30_Records/{YYYY}/{category}/{title}.md.
    # category는 자유 텍스트(SPEC §8.2). datalist로 distinct 자동완성.
    class RecordsController < ApplicationController
      PER_PAGE = 30
      MAX_PAGE = 10_000

      ERROR_MESSAGES = {
        empty_title: "제목을 입력해 주세요.",
        empty_body: "본문을 입력해 주세요.",
        empty_category: "카테고리를 입력해 주세요.",
        not_found: "기록을 찾을 수 없습니다.",
        file_missing: "기록 파일이 존재하지 않습니다."
      }.freeze

      helpers do
        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        end

        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        def create_record_use_case
          UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def update_record_use_case
          UseCases::UpdateRecord.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def parse_tags(raw)
          raw.to_s.split(/[\s,]+/).reject(&:empty?)
        end

        def error_message(failure)
          ERROR_MESSAGES.fetch(failure, "저장 실패: #{failure}")
        end

        def find_record(id)
          indexed = index_repo.find(id)
          return nil if indexed.nil? || indexed.mode != :record
          vault_repo.read(indexed.path)
        rescue Errno::ENOENT
          nil
        end

        def record_to_form(record)
          {
            title: record.title,
            body: record.body,
            category: record.category,
            promoted_from: record.promoted_from,
            tags: record.tags.to_a.join(", ")
          }
        end

        def load_record_page(page:, per_page:, category: nil)
          offset = (page - 1) * per_page
          index_repo.list(mode: :record, category: category, limit: per_page, offset: offset).filter_map do |indexed|
            vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            nil
          end
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

      get "/records" do
        @page_title = "기록"
        @page = (params["page"] || 1).to_i.clamp(1, MAX_PAGE)
        @per_page = PER_PAGE
        @category = params["category"].to_s.empty? ? nil : params["category"]
        @categories = index_repo.distinct_categories(mode: :record)
        @category = nil if @category && !@categories.include?(@category)
        @total = index_repo.count(mode: :record, category: @category)
        @total_pages = [(@total / @per_page.to_f).ceil, 1].max
        @records = load_record_page(page: @page, per_page: @per_page, category: @category)
        erb :"records/index", layout: :"layouts/application"
      end

      get "/records/new" do
        @page_title = "기록 작성"
        @form = empty_form
        @categories = index_repo.distinct_categories(mode: :record)
        @error = nil
        erb :"records/new", layout: :"layouts/application"
      end

      get "/records/:id" do
        @record = find_record(params["id"])
        halt_with_404(ERROR_MESSAGES[:not_found]) if @record.nil?
        @page_title = @record.title
        erb :"records/show", layout: :"layouts/application"
      end

      get "/records/:id/edit" do
        @record = find_record(params["id"])
        halt_with_404(ERROR_MESSAGES[:not_found]) if @record.nil?

        @page_title = "기록 편집"
        @form = record_to_form(@record)
        @categories = index_repo.distinct_categories(mode: :record)
        @expected_file_hash = vault_repo.file_hash(index_repo.find(@record.id).path)
        @error = nil
        erb :"records/edit", layout: :"layouts/application"
      end

      post "/records" do
        result = create_record_use_case.call(
          title: params["title"].to_s,
          body: params["body"].to_s,
          category: params["category"].to_s,
          tags: parse_tags(params["tags"]),
          promoted_from: blank?(params["promoted_from"]) ? nil : params["promoted_from"]
        )

        if result.success?
          redirect "/records/#{result.value!.id}"
        else
          @page_title = "기록 작성"
          @form = form_from_params
          @categories = index_repo.distinct_categories(mode: :record)
          @error = error_message(result.failure)
          status 422
          erb :"records/new", layout: :"layouts/application"
        end
      end

      patch "/records/:id" do
        force = truthy?(params["force"])
        result = update_record_use_case.call(
          id: params["id"],
          title: params["title"].to_s,
          body: params["body"].to_s,
          category: params["category"].to_s,
          tags: parse_tags(params["tags"]),
          promoted_from: blank?(params["promoted_from"]) ? nil : params["promoted_from"],
          expected_file_hash: params["expected_file_hash"],
          force: force
        )

        if result.success?
          redirect "/records/#{result.value!.id}"
        elsif conflict?(result)
          @record = find_record(params["id"])
          @page_title = "충돌 감지"
          @conflict = result.failure[1]
          @kind = :record
          status 409
          erb :"shared/_conflict", layout: :"layouts/application"
        elsif [:not_found, :file_missing].include?(result.failure)
          halt_with_404(ERROR_MESSAGES[result.failure])
        else
          @record = find_record(params["id"])
          @page_title = "기록 편집"
          @form = form_from_params
          @categories = index_repo.distinct_categories(mode: :record)
          @expected_file_hash = params["expected_file_hash"]
          @error = error_message(result.failure)
          status 422
          erb :"records/edit", layout: :"layouts/application"
        end
      end

      private

      def empty_form
        {title: nil, body: nil, category: nil, promoted_from: nil, tags: nil}
      end

      def form_from_params
        {
          title: params["title"],
          body: params["body"],
          category: params["category"],
          promoted_from: params["promoted_from"],
          tags: params["tags"]
        }
      end

      def blank?(value)
        value.to_s.strip.empty?
      end
    end
  end
end
