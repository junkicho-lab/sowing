# frozen_string_literal: true

module Sowing
  module Controllers
    # Phase 13 W26-T03 — '쓴 글 보기' 통합 진입점.
    #
    # 메모·필기·기록 3 mode 를 하나의 시간순 리스트로 표시. 기존 /memos
    # /notes /records 는 mode 별 진입이지만, 사용자 머릿속 "최근에 뭐 적었지"
    # 는 mode 무관 — 그 의도에 맞춤.
    #
    # 라우트:
    #   GET /view         → /view/recent redirect
    #   GET /view/recent  → 최근 시간순 통합 리스트 (메모/필기/기록)
    #     params:
    #       mode    — memo|note|record|nil (nil 이면 전체)
    #       category — 필터 (kebab/한글 모두 지원)
    #       limit   — 기본 100, 최대 300
    #
    # ADR-014 (제안): 동사 mode (보기) 와 명사 mode (메모/필기/기록) 분리.
    # /view/recent 는 사용자 의도, IndexRepo.recent_across 는 저장 단위 합집합.
    class ViewController < ApplicationController
      MAX_LIMIT = 300
      DEFAULT_LIMIT = 100

      helpers do
        def view_index_repo
          @view_index_repo ||= Repositories::IndexRepo.new
        end

        def view_vault_repo
          @view_vault_repo ||= Repositories::VaultRepo.new(vault_dir: Core::Paths.vault_dir)
        end

        # entries 의 본문 첫 N 글자 발췌.
        # VaultRepo.read 는 mode 별 reconstruct (Memo/Note/Record) 만 알고 :plan 거부.
        # 따라서 직접 파일 읽기 + frontmatter 제거 — mode-agnostic.
        # 파일 누락 시 빈 문자열 — graceful (인덱스 정합성 깨진 경우).
        def view_body_excerpt(indexed_entry, limit: 160)
          full_path = Core::Paths.vault_dir.join(indexed_entry.path)
          raw = File.read(full_path, encoding: "UTF-8")
          # frontmatter 제거 + H1 (`# title`) 제거 후 발췌
          body = raw.sub(/\A---\n.*?\n---\n+/m, "").sub(/\A# .+\n+/, "").strip
          body[0, limit]
        rescue Errno::ENOENT
          ""
        end

        def view_mode_label(mode)
          case mode.to_sym
          when :memo then "💭 메모"
          when :note then "📝 필기"
          when :record then "📖 기록"
          when :plan then "🗓 계획"
          else mode.to_s
          end
        end

        def view_mode_path(entry)
          mode_dir = case entry.mode.to_sym
          when :memo then "memos"
          when :note then "notes"
          when :record then "records"
          when :plan then "plans"
          end
          "/#{mode_dir}/#{entry.id}"
        end
      end

      get "/view" do
        redirect "/view/recent"
      end

      get "/view/recent" do
        @page_title = "최근 (통합)"
        @selected_mode = (%w[memo note record plan].include?(params["mode"]) ? params["mode"] : nil)
        @selected_category = params["category"].to_s.strip.empty? ? nil : params["category"]
        @limit = parse_limit(params["limit"])

        # 인덱스에서 시간순 일괄 조회 — 합성기·검색과 무관한 빠른 경로.
        entries = view_index_repo.recent_across(limit: @limit * 2) # 필터 여지 위해 2x

        entries = entries.select { |e| e.mode.to_s == @selected_mode } if @selected_mode
        entries = entries.select { |e| e.category == @selected_category } if @selected_category
        @entries = entries.first(@limit)

        # 카테고리 chip 후보 (현재 데이터 기준 — 동적)
        @available_categories = view_index_repo
          .recent_across(limit: 500)
          .map(&:category)
          .compact
          .uniq
          .sort

        erb :"view/recent", layout: :"layouts/application"
      end

      private

      def parse_limit(raw)
        v = raw.to_s.to_i
        return DEFAULT_LIMIT if v <= 0
        [v, MAX_LIMIT].min
      end
    end
  end
end
