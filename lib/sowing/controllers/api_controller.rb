# frozen_string_literal: true

require "json"

module Sowing
  module Controllers
    # 클라이언트(Stimulus 자동완성 등)용 JSON API.
    # ADR-004 위키링크 자동완성 응답 형식 준수.
    class ApiController < ApplicationController
      ICONS = {"memo" => "💭", "note" => "📝", "record" => "📖"}.freeze
      LIMIT = 25
      MEMO_EXCERPT_LIMIT = 60

      helpers do
        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        def vault_repo
          @vault_repo ||= Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        end
      end

      get "/api/wiki_complete" do
        content_type :json
        q = params["q"].to_s.strip
        rows = index_repo.complete(q: q, limit: LIMIT)

        results = rows.map do |row|
          {
            path: row[:path],
            title: display_title(row),
            mode: row[:mode],
            icon: ICONS[row[:mode]]
          }
        end

        {results: results}.to_json
      end

      private

      # ADR-004: memo는 title이 없으므로 본문 첫 60자를 "(메모) ..." 형식으로 표시.
      def display_title(row)
        if row[:mode] == "memo"
          excerpt = read_memo_body(row[:path]).strip[0, MEMO_EXCERPT_LIMIT].to_s
          "(메모) #{excerpt}"
        else
          row[:title].to_s
        end
      end

      def read_memo_body(rel_path)
        memo = vault_repo.read(rel_path)
        memo.body
      rescue Errno::ENOENT
        ""
      end
    end
  end
end
