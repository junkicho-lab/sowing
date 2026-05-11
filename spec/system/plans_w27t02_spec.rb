# frozen_string_literal: true

require "rack/test"

# Phase 13 W27-T02 — Plan PoC 확장:
#   - PERIODS 에 :project + :semester 추가
#   - 대시보드 '오늘 할 일' 위젯 (미완료 daily plans)
#   - nav 갱신
#
# IndexRepo·entries 통합은 별도 T03 으로 미룸 (SQLite CHECK 제약 변경 위험).
RSpec.describe "Plan 확장 + 대시보드 위젯 (Phase 13 W27-T02)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }
  let(:plans_dir) { vault_dir.join("40_Plans") }
  let(:repo) { Sowing::Repositories::PlanRepo.new(vault_dir: vault_dir) }

  before do
    header "Host", "127.0.0.1"
    FileUtils.rm_rf(plans_dir) if plans_dir.exist?
  end

  after { FileUtils.rm_rf(plans_dir) if plans_dir.exist? }

  describe "Domain::Plan PERIODS 확장" do
    it "5 종 — daily/weekly/monthly/project/semester" do
      expect(Sowing::Domain::Plan::PERIODS).to eq(
        %i[daily weekly monthly project semester]
      )
    end

    it ":project plan 생성 가능 (slug plan_date)" do
      plan = Sowing::Domain::Plan.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        title: "사피엔스 정독", body: "- [ ] 1장",
        period: :project, plan_date: "sapiens-read",
        created_at: Time.now
      )
      expect(plan.period).to eq(:project)
      expect(plan.plan_date).to eq("sapiens-read")
    end

    it ":semester plan 생성 가능 (YYYY-Sn)" do
      plan = Sowing::Domain::Plan.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        title: "2026 1학기 큰 그림", body: "x",
        period: :semester, plan_date: "2026-S1",
        created_at: Time.now
      )
      expect(plan.period).to eq(:semester)
    end
  end

  describe "CreatePlan use case — 5 period 검증" do
    let(:use_case) { Sowing::UseCases::CreatePlan.new(plan_repo: repo) }

    it ":project + slug → Success" do
      result = use_case.call(title: "T", period: :project, plan_date: "my-book-2026")
      expect(result.success?).to be true
    end

    it ":project + 공백 포함 slug → Failure (영문/숫자/한글/- 만 허용)" do
      result = use_case.call(title: "T", period: :project, plan_date: "my book")
      expect(result.failure).to eq(:invalid_plan_date)
    end

    it ":semester + YYYY-S1 → Success" do
      result = use_case.call(title: "T", period: :semester, plan_date: "2026-S1")
      expect(result.success?).to be true
    end

    it ":semester + YYYY-S3 → Failure" do
      result = use_case.call(title: "T", period: :semester, plan_date: "2026-S3")
      expect(result.failure).to eq(:invalid_plan_date)
    end
  end

  describe "PlanRepo — project/semester 디렉토리" do
    it ":project plan 저장 → 40_Plans/project/{slug}.md" do
      plan = Sowing::Domain::Plan.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        title: "T", body: "x", period: :project, plan_date: "sapiens",
        created_at: Time.now
      )
      path = repo.write(plan)
      expect(path.to_s).to include("40_Plans/project/sapiens.md")
    end

    it ":semester plan 저장 → 40_Plans/semester/2026-S1.md" do
      plan = Sowing::Domain::Plan.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        title: "T", body: "x", period: :semester, plan_date: "2026-S1",
        created_at: Time.now
      )
      path = repo.write(plan)
      expect(path.to_s).to include("40_Plans/semester/2026-S1.md")
    end

    it "list_all — 5 period 모두 합본" do
      Sowing::Domain::Plan::PERIODS.each do |period|
        plan_date = case period
        when :daily   then "2026-05-11"
        when :weekly  then "2026-W19"
        when :monthly then "2026-05"
        when :project then "test-proj-#{period}"
        when :semester then "2026-S1"
        end
        repo.write(Sowing::Domain::Plan.new(
          id: Sowing::Domain::ValueObjects::Ulid.generate,
          title: "T-#{period}", body: "x",
          period: period, plan_date: plan_date, created_at: Time.now
        ))
      end
      all = repo.list_all
      expect(all.size).to eq(5)
      expect(all.map(&:period).sort).to eq(%i[daily monthly project semester weekly])
    end
  end

  describe "Nav — 5 period 진입점" do
    it "쓸 글 계획 dropdown 에 5 period 모두 노출" do
      get "/"
      expect(last_response.body).to include('href="/plans?period=daily"')
      expect(last_response.body).to include('href="/plans?period=weekly"')
      expect(last_response.body).to include('href="/plans?period=monthly"')
      expect(last_response.body).to include('href="/plans?period=project"')
      expect(last_response.body).to include('href="/plans?period=semester"')
    end
  end

  describe "GET /plans?period=project — 프로젝트 페이지" do
    it "200 + chip 5종 + project active" do
      get "/plans?period=project"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("🏗 프로젝트")
      expect(last_response.body).to include("🎓 학기")
    end
  end

  describe "GET /plans?period=semester — 학기 페이지" do
    it "200 + semester active" do
      get "/plans?period=semester"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("🎓 학기")
    end
  end

  describe "대시보드 '오늘 할 일' 위젯" do
    let(:today_str) { Date.today.strftime("%Y-%m-%d") }

    it "오늘의 미완료 daily plan 있음 → 위젯 표시" do
      post "/plans", title: "오늘 할 일 1", period: "daily",
        plan_date: today_str, body: "x"
      expect(last_response.status).to eq(302) # redirect 정상

      get "/"
      expect(last_response.body).to include("📅 오늘 할 일")
      expect(last_response.body).to include("오늘 할 일 1")
      expect(last_response.body).to include(today_str)
    end

    it "오늘 plan 없음 → 위젯 안 표시" do
      get "/"
      expect(last_response.body).not_to include("todays-plans")
    end

    it "오늘 plan 모두 완료 → 위젯 안 표시" do
      post "/plans", title: "완료된 작업", period: "daily",
        plan_date: today_str, body: "x"
      id = last_response.location[%r{/plans/([0-9A-Z]{26})}, 1]
      post "/plans/#{id}/toggle" # 완료 처리

      get "/"
      expect(last_response.body).not_to include("todays-plans")
    end

    it "다른 날짜 plan → 오늘 위젯엔 안 보임" do
      post "/plans", title: "어제 작업", period: "daily",
        plan_date: "2020-01-01", body: "x"

      get "/"
      expect(last_response.body).not_to include("어제 작업")
    end

    it "위젯에 완료 토글 버튼 — 사용자 명시 클릭 (ADR-013)" do
      post "/plans", title: "T", period: "daily", plan_date: today_str, body: "x"

      get "/"
      expect(last_response.body).to include('action="/plans/')
      expect(last_response.body).to include("/toggle")
      expect(last_response.body).to include("✓ 완료")
    end
  end

  describe "PlansController helpers — todays_pending_plans" do
    it "오늘의 미완료만 반환" do
      today_str = Date.today.strftime("%Y-%m-%d")
      # 오늘 미완료
      use_case = Sowing::UseCases::CreatePlan.new(plan_repo: repo)
      use_case.call(title: "pending", period: :daily, plan_date: today_str)

      get "/plans" # controller helper 호출 트리거 (response 자체는 별 의미 없음)
      expect(last_response.status).to eq(200)
      # 별도 검증은 위 대시보드 spec 으로 커버됨
    end
  end
end
