# frozen_string_literal: true

require "rack/test"

# Phase 13 W27-T01 — 쓸 글 계획 (Plan mode) PoC.
# IndexRepo·entries 테이블 통합은 W27-T02 (별도). 본 spec 은 파일 시스템 기반.
RSpec.describe "쓸 글 계획 (Phase 13 W27-T01)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }
  let(:plans_dir) { vault_dir.join("40_Plans") }

  before do
    header "Host", "127.0.0.1"
    FileUtils.rm_rf(plans_dir) if plans_dir.exist?
    # W27-T03: PlanRepo 가 entries 테이블에도 인덱싱 — 격리 위해 cleanup
    db = Sowing::Infrastructure::DB.connection
    %i[entries_fts links entry_tags tags entries].each { |t| db[t].delete }
  end

  after { FileUtils.rm_rf(plans_dir) if plans_dir.exist? }

  describe "Domain::Plan" do
    let(:valid_attrs) do
      {
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        title: "협동학습 평가 정리",
        body: "- [ ] 루브릭 작성\n- [ ] 학생 자료 수집",
        period: :daily,
        plan_date: "2026-05-11",
        created_at: Time.now
      }
    end

    it "필수 속성으로 생성 가능" do
      plan = Sowing::Domain::Plan.new(**valid_attrs)
      expect(plan.title).to eq("협동학습 평가 정리")
      expect(plan.period).to eq(:daily)
      expect(plan.done).to be false
      expect(plan.mode).to eq(:plan)
    end

    it "frontmatter 직렬화" do
      plan = Sowing::Domain::Plan.new(**valid_attrs)
      fm = plan.to_frontmatter
      expect(fm["mode"]).to eq("plan")
      expect(fm["period"]).to eq("daily")
      expect(fm["plan_date"]).to eq("2026-05-11")
      expect(fm["done"]).to be false
    end

    it "잘못된 period → ArgumentError" do
      expect {
        Sowing::Domain::Plan.new(**valid_attrs, period: :hourly)
      }.to raise_error(ArgumentError, /period/)
    end

    it "frozen — 불변" do
      plan = Sowing::Domain::Plan.new(**valid_attrs)
      expect(plan.frozen?).to be true
    end
  end

  describe "PlanRepo" do
    let(:repo) { Sowing::Repositories::PlanRepo.new(vault_dir: vault_dir) }
    let(:plan) do
      Sowing::Domain::Plan.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        title: "협동학습 평가",
        body: "- [ ] 루브릭",
        period: :daily,
        plan_date: "2026-05-11",
        created_at: Time.now
      )
    end

    it "write + read 왕복 — 마크다운 파일 라운드트립" do
      path = repo.write(plan)
      expect(path.to_s).to include("40_Plans/daily/2026-05-11.md")
      restored = repo.read(path)
      expect(restored.title).to eq(plan.title)
      expect(restored.period).to eq(plan.period)
      expect(restored.plan_date).to eq(plan.plan_date)
      expect(restored.done).to be false
    end

    it "list_by_period — period 디렉토리 안의 파일 모두" do
      repo.write(plan)
      list = repo.list_by_period(:daily)
      expect(list.size).to eq(1)
      expect(list.first.title).to eq(plan.title)
    end

    it "find_by_id — 모든 period 디렉토리 스캔" do
      repo.write(plan)
      result = repo.find_by_id(plan.id.to_s)
      expect(result).not_to be_nil
      found_plan, _path = result
      expect(found_plan.id.to_s).to eq(plan.id.to_s)
    end

    it "toggle_done — frontmatter done 토글 + 파일 갱신" do
      repo.write(plan)
      toggled = repo.toggle_done(plan.id.to_s)
      expect(toggled.done).to be true
      again = repo.toggle_done(plan.id.to_s)
      expect(again.done).to be false
    end
  end

  describe "CreatePlan use case" do
    let(:repo) { Sowing::Repositories::PlanRepo.new(vault_dir: vault_dir) }
    let(:use_case) { Sowing::UseCases::CreatePlan.new(plan_repo: repo) }

    it "정상 생성 → Success(Plan)" do
      result = use_case.call(title: "테스트", period: :daily, plan_date: "2026-05-11", body: "본문")
      expect(result.success?).to be true
      expect(result.value!.title).to eq("테스트")
    end

    it "빈 제목 → Failure(:empty_title)" do
      result = use_case.call(title: "", period: :daily, plan_date: "2026-05-11")
      expect(result.failure).to eq(:empty_title)
    end

    it "잘못된 period → Failure(:invalid_period)" do
      result = use_case.call(title: "T", period: :yearly, plan_date: "2026")
      expect(result.failure).to eq(:invalid_period)
    end

    it "잘못된 plan_date 형식 (daily 인데 YYYY-MM) → Failure(:invalid_plan_date)" do
      result = use_case.call(title: "T", period: :daily, plan_date: "2026-05")
      expect(result.failure).to eq(:invalid_plan_date)
    end

    it "본문에서 #태그 자동 추출" do
      # use case 직접 호출은 태그를 인자로 받음 — controller 레벨에서 추출.
      # 본 spec 은 별도 controller spec 에서 검증.
    end
  end

  describe "GET /plans" do
    it "200 + period chip 3종 표시" do
      get "/plans"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("📅 일간")
      expect(last_response.body).to include("📋 주간")
      expect(last_response.body).to include("🎯 월간")
    end

    it "빈 상태 — '계획이 없습니다' 안내" do
      get "/plans"
      expect(last_response.body).to include("계획이 없습니다")
    end

    it "?period=weekly → weekly chip active" do
      get "/plans?period=weekly"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("plans__chip--active")
    end
  end

  describe "POST /plans — 신규 생성" do
    it "정상 입력 → 생성 + redirect" do
      post "/plans", title: "통합학습 차시 설계", period: "daily", plan_date: "2026-05-11", body: "- [ ] 1차시"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to match(%r{/plans/[0-9A-Z]{26}})
    end

    it "빈 제목 → 다시 new 폼으로 (flash 안내)" do
      post "/plans", title: "", period: "daily", plan_date: "2026-05-11"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include("/plans/new")
    end
  end

  describe "GET /plans/:id 상세" do
    it "생성된 plan 상세 + 토글 버튼" do
      post "/plans", title: "Test", period: "daily", plan_date: "2026-05-11", body: "본문"
      id = last_response.location[%r{/plans/([0-9A-Z]{26})}, 1]

      get "/plans/#{id}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Test")
      expect(last_response.body).to include("완료 표시")
    end

    it "없는 id → 404" do
      get "/plans/01KRINVALID00000000000000A"
      expect(last_response.status).to eq(404)
    end
  end

  describe "POST /plans/:id/toggle — 완료 토글" do
    it "미완료 → 완료" do
      post "/plans", title: "T", period: "daily", plan_date: "2026-05-11", body: "x"
      id = last_response.location[%r{/plans/([0-9A-Z]{26})}, 1]

      post "/plans/#{id}/toggle"
      expect(last_response.status).to eq(302)

      get "/plans/#{id}"
      expect(last_response.body).to include("완료")
      expect(last_response.body).to include("다시 진행 중으로")
    end
  end

  describe "Nav 통합" do
    it "'쓸 글 계획' dropdown 의 3 period 진입점 노출" do
      get "/"
      expect(last_response.body).to include('href="/plans?period=daily"')
      expect(last_response.body).to include('href="/plans?period=weekly"')
      expect(last_response.body).to include('href="/plans?period=monthly"')
      expect(last_response.body).to include('href="/plans/new?period=daily"')
    end

    it "GET /plan → /plans redirect (NavController 의 동사 진입점)" do
      get "/plan"
      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/plans")
    end
  end
end
