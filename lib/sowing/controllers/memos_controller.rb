# frozen_string_literal: true

module Sowing
  module Controllers
    # 메모 작성·표시. POST /memos는 빠른 메모 모달의 제출을 받아 처리.
    # Turbo Stream으로 응답하여 페이지 리로드 없이 대시보드 갱신.
    class MemosController < ApplicationController
      TURBO_STREAM_TYPE = "text/vnd.turbo-stream.html"
      PER_PAGE = 30
      MAX_PAGE = 10_000

      helpers do
        def create_memo_use_case
          UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        end

        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
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
    end
  end
end
