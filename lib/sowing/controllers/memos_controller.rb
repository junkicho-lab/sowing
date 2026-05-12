# frozen_string_literal: true

module Sowing
  module Controllers
    # 메모 작성·표시. POST /memos는 빠른 메모 모달의 제출을 받아 처리.
    # Turbo Stream으로 응답하여 페이지 리로드 없이 대시보드 갱신.
    class MemosController < ApplicationController
      TURBO_STREAM_TYPE = "text/vnd.turbo-stream.html"
      PER_PAGE = 30
      MAX_PAGE = 10_000

      NOTE_CATEGORIES = UseCases::CreateNote::CATEGORIES

      ERROR_MESSAGES = {
        empty_title: "제목을 입력해 주세요.",
        empty_category: "카테고리를 입력해 주세요.",
        invalid_category: "유효하지 않은 카테고리입니다.",
        empty_source: "출처를 입력해 주세요.",
        not_found: "메모를 찾을 수 없습니다.",
        not_a_memo: "이 항목은 메모가 아닙니다.",
        not_promotable: "이 항목은 승격 대상이 아닙니다.",
        file_missing: "메모 파일이 존재하지 않습니다."
      }.freeze

      helpers do
        def create_memo_use_case
          UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def promote_to_note_use_case
          UseCases::PromoteToNote.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def promote_to_record_use_case
          UseCases::PromoteToRecord.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Core::Paths.vault_dir)
        end

        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        # 페이지의 메모 도메인 객체. 인덱스로 페이징, body는 파일에서.
        def load_memo_page(page:, per_page:)
          offset = (page - 1) * per_page
          index_repo.list(mode: :memo, limit: per_page, offset: offset).filter_map do |indexed|
            vault_repo.read(indexed.path)
          rescue Errno::ENOENT
            nil
          end
        end

        def find_memo(id)
          indexed = index_repo.find(id)
          return nil if indexed.nil? || indexed.mode != :memo
          vault_repo.read(indexed.path)
        rescue Errno::ENOENT
          nil
        end

        def note_categories
          NotesController::CATEGORIES
        end

        def parse_tags(raw)
          raw.to_s.split(/[\s,]+/).reject(&:empty?)
        end

        def memo_error_message(failure)
          ERROR_MESSAGES.fetch(failure, "처리 실패: #{failure}")
        end

        def halt_with_404(message)
          status 404
          @page_title = "찾을 수 없음"
          @message = message
          halt erb(:"errors/404", layout: :"layouts/application")
        end
      end

      get "/memos" do
        @page_title = "메모"
        @page = (params["page"] || 1).to_i.clamp(1, MAX_PAGE)
        @per_page = PER_PAGE
        @total = index_repo.count(mode: :memo)
        @total_pages = [(@total / @per_page.to_f).ceil, 1].max
        @memos = load_memo_page(page: @page, per_page: @per_page)
        erb :"memos/index", layout: :"layouts/application"
      end

      post "/memos" do
        body = params["body"].to_s
        result = create_memo_use_case.call(body: body)

        if result.success?
          memo = result.value!
          content_type TURBO_STREAM_TYPE
          erb :"memos/created.turbo_stream", layout: false, locals: {memo: memo}
        else
          status 422
          content_type TURBO_STREAM_TYPE
          erb :"memos/error.turbo_stream", layout: false, locals: {failure: result.failure}
        end
      end

      get "/memos/:id/promote_to_note" do
        @memo = find_memo(params["id"])
        halt_with_404(ERROR_MESSAGES[:not_found]) if @memo.nil?

        @page_title = "필기로 승격"
        @form = {
          title: nil,
          category: nil,
          source: nil,
          tags: @memo.tags.to_a.join(", ")
        }
        @error = nil
        erb :"memos/promote_to_note", layout: :"layouts/application"
      end

      post "/memos/:id/promote_to_note" do
        result = promote_to_note_use_case.call(
          id: params["id"],
          title: params["title"].to_s,
          category: params["category"].to_s,
          source: params["source"].to_s,
          tags: parse_tags(params["tags"])
        )

        if result.success?
          redirect "/notes/#{result.value!.id}"
        elsif [:not_found, :not_a_memo, :file_missing].include?(result.failure)
          halt_with_404(memo_error_message(result.failure))
        else
          @memo = find_memo(params["id"]) || halt_with_404(ERROR_MESSAGES[:not_found])
          @page_title = "필기로 승격"
          @form = {
            title: params["title"],
            category: params["category"],
            source: params["source"],
            tags: params["tags"]
          }
          @error = memo_error_message(result.failure)
          status 422
          erb :"memos/promote_to_note", layout: :"layouts/application"
        end
      end

      get "/memos/:id/promote_to_record" do
        @memo = find_memo(params["id"])
        halt_with_404(ERROR_MESSAGES[:not_found]) if @memo.nil?

        @page_title = "기록으로 승격"
        @form = {
          title: nil,
          category: nil,
          tags: @memo.tags.to_a.join(", ")
        }
        @categories = index_repo.distinct_categories(mode: :record)
        @error = nil
        erb :"memos/promote_to_record", layout: :"layouts/application"
      end

      post "/memos/:id/promote_to_record" do
        result = promote_to_record_use_case.call(
          id: params["id"],
          title: params["title"].to_s,
          category: params["category"].to_s,
          tags: parse_tags(params["tags"])
        )

        if result.success?
          redirect "/records/#{result.value!.id}"
        elsif [:not_found, :not_promotable, :file_missing].include?(result.failure)
          halt_with_404(memo_error_message(result.failure))
        else
          @memo = find_memo(params["id"]) || halt_with_404(ERROR_MESSAGES[:not_found])
          @page_title = "기록으로 승격"
          @form = {
            title: params["title"],
            category: params["category"],
            tags: params["tags"]
          }
          @categories = index_repo.distinct_categories(mode: :record)
          @error = memo_error_message(result.failure)
          status 422
          erb :"memos/promote_to_record", layout: :"layouts/application"
        end
      end
    end
  end
end
