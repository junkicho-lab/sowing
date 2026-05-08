# frozen_string_literal: true

module Sowing
  module Controllers
    # 태그 — 태그 클라우드 + 태그별 entries 목록.
    # 태그 정규화: TagSet 정책(strip + downcase). 본문 #태그도 union 인덱싱 (W3-T05).
    class TagsController < ApplicationController
      helpers do
        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        end

        def entry_link_for(indexed)
          case indexed.mode
          when :note then "/notes/#{indexed.id}"
          when :record then "/records/#{indexed.id}"
          else "/memos" # memo는 개별 show 미구현 — 목록으로 (W3+에서 개별 show 추가 가능)
          end
        end

        def mode_icon(mode)
          {memo: "💭", note: "📝", record: "📖"}[mode.to_sym]
        end

        def mode_label(mode)
          {memo: "메모", note: "필기", record: "기록"}[mode.to_sym]
        end
      end

      get "/tags" do
        @page_title = "태그"
        @tag_cloud = index_repo.tag_cloud
        erb :"tags/index", layout: :"layouts/application"
      end

      get "/tags/:name" do
        @tag = params["name"].to_s
        @page_title = "##{@tag}"
        @entries = index_repo.search_by_tag(@tag)
        erb :"tags/show", layout: :"layouts/application"
      end
    end
  end
end
