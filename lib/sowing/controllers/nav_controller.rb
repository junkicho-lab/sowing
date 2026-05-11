# frozen_string_literal: true

module Sowing
  module Controllers
    # Phase 13 W25-T01 — 동사 중심 IA 통합 진입점.
    #
    # 새 nav (글쓰기·쓴 글 보기·쓸 글 계획·자기 거울) 의 1급 클릭 시
    # 진입할 통합 페이지. PoC 단계에선 기존 라우트로 redirect — 통합
    # view 페이지 (예: /view 의 메모·필기·기록 시간순 합본) 는 W26+ 에 구현.
    #
    # 라우트:
    #   GET /write    → /memos (W26 에서 subtype 선택 페이지로 교체)
    #   GET /view     → /records (W26 에서 시간순 통합 리스트로 교체)
    #   GET /plan     → /settings (W27 에서 Plan mode 페이지로 교체) + flash 안내
    #   GET /mirror   → /synth (W28 에서 self-mirror 위젯 통합)
    #
    # 기존 라우트 (/memos, /notes, /records, /tags, /search, /synth, /graph) 는
    # 그대로 작동 — 북마크·외부 링크 호환.
    #
    # ADR-014 (제안): 명사 mode (메모·필기·기록·계획·합성) = 저장 단위,
    # 동사 mode (글쓰기·보기·계획·회고) = 의도 단위. 두 계층 명시 분리.
    class NavController < ApplicationController
      # W26-T01 부분 구현 — /write 일반 + /write/{subtype} 5개.
      # dashboard (/) 로 redirect + ?write=subtype query param.
      # quick_memo_controller.js connect() 가 param 읽어 모달 자동 열기 + chip prefill.
      VALID_WRITE_SUBTYPES = %w[general book lecture emotion student].freeze

      get "/write" do
        redirect "/?write=general"
      end

      get "/write/:subtype" do
        subtype = params["subtype"].to_s
        subtype = "general" unless VALID_WRITE_SUBTYPES.include?(subtype)
        redirect "/?write=#{subtype}"
      end

      # /view 는 ViewController 가 처리 — NavController 에서는 라우트 정의 안 함.
      # (Sinatra mount 순서로 인해 ViewController 가 먼저 매칭됨)

      # W27-T01 — Plan mode 실 구현. /plan → /plans redirect (명사 mode 진입점).
      get "/plan" do
        redirect "/plans"
      end

      get "/mirror" do
        # W28 에서 self-mirror 위젯 + 5축 자아 분석 합성기 진입점으로 교체.
        # 현재는 기존 합성기 대시보드 (16종, /synth) 로 진입.
        redirect "/synth"
      end
    end
  end
end
