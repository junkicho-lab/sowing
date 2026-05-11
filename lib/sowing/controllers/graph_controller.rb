# frozen_string_literal: true

require "json"

module Sowing
  module Controllers
    # 위키링크 그래프 시각화 (30년 시나리오 #4).
    #
    # `GET /graph` — 페이지 (필터 폼 + SVG 컨테이너)
    # `GET /api/graph_data` — JSON (Stimulus controller 가 fetch)
    #
    # 데이터 소스: IndexRepo#graph_data (entries + links 테이블).
    # 시각화: 순수 인라인 SVG + 자체 force-directed (외부 라이브러리 0).
    # CLAUDE.md 원칙 준수 — importmap·esm 외 빌드 도구 안 씀.
    class GraphController < ApplicationController
      DEFAULT_MAX_NODES = 200

      helpers do
        def graph_index_repo
          @graph_index_repo ||= Repositories::IndexRepo.new
        end

        def parse_date_q(value)
          return nil if value.to_s.strip.empty?
          Time.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def parse_array_q(value)
          arr = Array(value).flatten.compact.reject(&:empty?)
          arr.empty? ? nil : arr
        end
      end

      # 그래프 페이지
      get "/graph" do
        @page_title = "위키링크 그래프"
        @categories_all = graph_index_repo.distinct_categories(mode: :note) +
          graph_index_repo.distinct_categories(mode: :record)
        @categories_all = @categories_all.uniq.sort
        @selected_modes = parse_array_q(params["modes"]) || %w[memo note record]
        @selected_categories = parse_array_q(params["categories"])
        @since = parse_date_q(params["since"])
        @until = parse_date_q(params["until"])
        @max_nodes = (params["max"] || DEFAULT_MAX_NODES).to_i.clamp(10, 1000)
        erb :"graph/index", layout: :"layouts/application"
      end

      # JSON API — Stimulus controller fetch
      get "/api/graph_data" do
        content_type :json
        modes = parse_array_q(params["modes"]) || %w[memo note record]
        cats = parse_array_q(params["categories"])
        since = parse_date_q(params["since"])
        until_time = parse_date_q(params["until"])
        max_nodes = (params["max"] || DEFAULT_MAX_NODES).to_i.clamp(10, 1000)

        data = graph_index_repo.graph_data(
          mode_in: modes,
          category_in: cats,
          since: since,
          until_time: until_time,
          max_nodes: max_nodes
        )
        # 라우팅용 path 정보 추가 (SVG node 클릭 시 entry 이동)
        mode_to_path = {"memo" => "memos", "note" => "notes", "record" => "records"}
        data[:nodes].each do |n|
          n[:href] = "/#{mode_to_path.fetch(n[:mode], "records")}/#{n[:id]}"
        end
        data.to_json
      end
    end
  end
end
