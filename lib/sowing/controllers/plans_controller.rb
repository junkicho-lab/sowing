# frozen_string_literal: true

module Sowing
  module Controllers
    # 쓸 글 계획 mode (Phase 13 W27-T01).
    #
    # 라우트:
    #   GET  /plans                — period 별 plan 목록 + 신규 작성 폼
    #   GET  /plans/new            — 신규 작성 폼 (?period=daily 같은 prefill)
    #   POST /plans                — 신규 plan 생성
    #   GET  /plans/:id            — plan 상세 + 본문 마크다운 렌더
    #   POST /plans/:id/toggle     — done 토글 (ADR-013 — 명시 클릭)
    #
    # ADR 호환:
    # - ADR-001 (SoT): 40_Plans/{period}/{date}.md 마크다운 파일이 단일 진실.
    # - ADR-009 (로컬-first): 영향 0.
    # - ADR-013 (자율 mutation 0): done 토글은 사용자 클릭으로만. 자동 완료 X.
    # - ADR-014 (제안): Plan 은 명사 mode (저장 단위) — 동사 nav '쓸 글 계획'
    #   진입점은 /plans 로 redirect.
    class PlansController < ApplicationController
      helpers do
        def plan_repo
          @plan_repo ||= Repositories::PlanRepo.new(
            vault_dir: Infrastructure::Paths.vault_dir
          )
        end

        def plan_create_use_case
          UseCases::CreatePlan.new(plan_repo: plan_repo)
        end

        def plan_period_label(period)
          {
            daily: "📅 일간",
            weekly: "📋 주간",
            monthly: "🎯 월간"
          }.fetch(period.to_sym, period.to_s)
        end

        # 오늘 기준 기본 plan_date — period 별 형식 다름.
        def plan_default_date(period, today: Date.today)
          case period.to_sym
          when :daily   then today.strftime("%Y-%m-%d")
          when :weekly  then today.strftime("%Y-W%V") # ISO 8601 week
          when :monthly then today.strftime("%Y-%m")
          end
        end
      end

      get "/plans" do
        @page_title = "쓸 글 계획"
        @selected_period = (Domain::Plan::PERIODS.map(&:to_s).include?(params["period"]) ? params["period"].to_sym : :daily)
        @plans_by_period = Domain::Plan::PERIODS.to_h { |p| [p, plan_repo.list_by_period(p)] }
        @selected_plans = @plans_by_period[@selected_period]
        @flash = session.delete(:flash)
        erb :"plans/index", layout: :"layouts/application"
      end

      get "/plans/new" do
        @page_title = "새 계획"
        @period = (Domain::Plan::PERIODS.map(&:to_s).include?(params["period"]) ? params["period"].to_sym : :daily)
        @default_date = plan_default_date(@period)
        erb :"plans/new", layout: :"layouts/application"
      end

      post "/plans" do
        period = params["period"].to_s
        result = plan_create_use_case.call(
          title: params["title"].to_s,
          period: period.empty? ? :daily : period.to_sym,
          plan_date: params["plan_date"].to_s,
          body: params["body"].to_s,
          tags: extract_tags(params["body"].to_s)
        )

        if result.success?
          plan = result.value!
          session[:flash] = "계획 생성됨: #{plan.title}"
          redirect "/plans/#{plan.id}"
        else
          session[:flash] = "생성 실패 (#{result.failure}) — 제목·기간·날짜 확인"
          redirect "/plans/new?period=#{period}"
        end
      end

      get "/plans/:id" do
        @page_title = "계획"
        result = plan_repo.find_by_id(params["id"])
        halt_with_404("계획을 찾을 수 없습니다: #{params["id"]}") unless result
        @plan, @plan_path = result
        @flash = session.delete(:flash)
        erb :"plans/show", layout: :"layouts/application"
      end

      post "/plans/:id/toggle" do
        toggled = plan_repo.toggle_done(params["id"])
        halt_with_404("계획을 찾을 수 없습니다") unless toggled
        session[:flash] = toggled.done ? "완료 처리: #{toggled.title}" : "재개 처리: #{toggled.title}"
        redirect "/plans/#{toggled.id}"
      end

      private

      # 본문에서 #tag 자동 추출 — 기존 Memo/Note 와 동일 패턴.
      def extract_tags(text)
        text.to_s.scan(/(?<![\w#])#([\w가-힣]+)/).flatten.uniq
      end

      def halt_with_404(msg)
        status 404
        halt erb(:"errors/404", layout: :"layouts/application", locals: {message: msg})
      end
    end
  end
end
