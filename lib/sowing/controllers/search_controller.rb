# frozen_string_literal: true

require "time"

module Sowing
  module Controllers
    # 검색 화면 (W4-T03).
    # GET /search?q=&mode=&category=&tag=&from=&to=&page=
    # 모든 필터 AND 결합. q는 IndexRepo가 한글 비율로 자동 라우팅 (FTS5 ↔ LIKE).
    class SearchController < ApplicationController
      PER_PAGE = 30
      MAX_PAGE = 10_000

      ALLOWED_MODES = {"memo" => :memo, "note" => :note, "record" => :record}.freeze

      helpers do
        def index_repo
          @index_repo ||= Repositories::IndexRepo.new
        end

        def mode_label(mode)
          {memo: "메모", note: "필기", record: "기록"}[mode.to_sym]
        end

        def mode_icon(mode)
          {memo: "💭", note: "📝", record: "📖"}[mode.to_sym]
        end

        def entry_link_for(entry)
          case entry.mode
          when :note then "/notes/#{entry.id}"
          when :record then "/records/#{entry.id}"
          else "/memos"
          end
        end

        def entry_display_title(entry)
          if entry.mode == :memo
            entry.title.to_s.empty? ? "(메모) #{entry.created_at.strftime("%Y-%m-%d %H:%M")}" : entry.title
          else
            entry.title.to_s
          end
        end

        def query_string_for(overrides = {})
          params_hash = {
            q: @q, mode: @mode, category: @category, tag: @tag,
            from: @from_str, to: @to_str
          }.merge(overrides).reject { |_, v| v.to_s.strip.empty? }
          return "" if params_hash.empty?
          "?" + params_hash.map { |k, v| "#{k}=#{Rack::Utils.escape(v.to_s)}" }.join("&")
        end
      end

      get "/search" do
        @page_title = "검색"
        @q = params["q"].to_s.strip
        @mode_str = params["mode"].to_s
        @mode = ALLOWED_MODES[@mode_str] # nil이면 mode 필터 없음
        @category = blank?(params["category"]) ? nil : params["category"]
        @tag = blank?(params["tag"]) ? nil : params["tag"]
        @from_str = params["from"].to_s
        @to_str = params["to"].to_s
        @from = parse_from_date(@from_str)
        @to = parse_to_date(@to_str)
        @page = (params["page"] || 1).to_i.clamp(1, MAX_PAGE)
        @per_page = PER_PAGE

        if any_filter?
          @total = index_repo.count_with_filters(
            q: @q, mode: @mode, category: @category, tag: @tag, from: @from, to: @to
          )
          @results = index_repo.search_with_filters(
            q: @q, mode: @mode, category: @category, tag: @tag, from: @from, to: @to,
            limit: @per_page, offset: (@page - 1) * @per_page
          )
        else
          @total = 0
          @results = []
        end

        @total_pages = [(@total / @per_page.to_f).ceil, 1].max
        @categories = index_repo.all_distinct_categories
        erb :"search/index", layout: :"layouts/application"
      end

      private

      def any_filter?
        !@q.empty? || @mode || @category || @tag || @from || @to
      end

      def blank?(value)
        value.to_s.strip.empty?
      end

      DATE_RE = /\A\d{4}-\d{2}-\d{2}\z/
      private_constant :DATE_RE

      # YYYY-MM-DD → Time at 00:00:00. Strict format check
      # (Time.parse는 너무 lenient — "not-a-dateT..." 같은 부분 매칭도 통과시킴).
      def parse_from_date(str)
        return nil if blank?(str)
        return nil unless str.strip.match?(DATE_RE)
        Time.parse("#{str.strip}T00:00:00")
      rescue ArgumentError
        nil
      end

      # YYYY-MM-DD → Time at 23:59:59 (해당 일자 끝, inclusive).
      def parse_to_date(str)
        return nil if blank?(str)
        return nil unless str.strip.match?(DATE_RE)
        Time.parse("#{str.strip}T23:59:59")
      rescue ArgumentError
        nil
      end
    end
  end
end
