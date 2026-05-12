# frozen_string_literal: true

require "rack/test"

# Phase 14 W32 — 같은 날짜에 여러 plan + 오전/오후 grouping.
RSpec.describe "같은 날짜 여러 plan + 오전/오후 grouping (Phase 14 W32)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }
  let(:plans_dir) { vault_dir.join("40_Plans") }
  let(:plan_repo) { Sowing::Repositories::PlanRepo.new(vault_dir: vault_dir) }

  before do
    header "Host", "127.0.0.1"
    FileUtils.rm_rf(plans_dir) if plans_dir.exist?
    %i[entries_fts links entry_tags tags entries].each { |t| db[t].delete }
    Sowing::Core::Settings.save(
      "onboarding_completed" => true,
      "ia_v2_seen_at" => "2026-05-11T00:00:00+09:00"
    )
  end

  after do
    FileUtils.rm_rf(plans_dir) if plans_dir.exist?
    Sowing::Core::Settings.reset!
  end

  describe "Path 규칙 — 같은 날짜 unique path" do
    it "daily/weekly/monthly: {date}-{HHmm}-{id4}.md" do
      Timecop.freeze(Time.new(2026, 5, 11, 9, 30, 0)) do
        result = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
          .call(title: "T1", period: :daily, plan_date: "2026-05-11")
        plan = result.value!
        path = vault_dir.join("40_Plans/daily/2026-05-11-0930-#{plan.id.to_s[-4..]}.md")
        expect(path.exist?).to be true
      end
    end

    it "project/semester: {date}-{id4}.md (시간 prefix 없음)" do
      result = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "T", period: :project, plan_date: "book-write")
      plan = result.value!
      path = vault_dir.join("40_Plans/project/book-write-#{plan.id.to_s[-4..]}.md")
      expect(path.exist?).to be true
    end
  end

  describe "같은 날짜에 여러 plan — UNIQUE 위반 0" do
    it "오전 + 오후 각각 별도 파일 + entries row 2 개" do
      Timecop.freeze(Time.new(2026, 5, 11, 9, 30, 0)) do
        Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
          .call(title: "오전 평가", period: :daily, plan_date: "2026-05-11")
      end
      Timecop.freeze(Time.new(2026, 5, 11, 14, 0, 0)) do
        Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
          .call(title: "오후 평가", period: :daily, plan_date: "2026-05-11")
      end

      # 두 파일 모두 존재
      files = Dir.glob(plans_dir.join("daily/*.md"))
      expect(files.size).to eq(2)

      # entries 도 2 row
      rows = db[:entries].where(mode: "plan").all
      expect(rows.size).to eq(2)
      expect(rows.map { |r| r[:title] }.sort).to eq(["오전 평가", "오후 평가"])
    end

    it "POST /plans 두 번 (같은 날짜) → 500 없이 둘 다 생성" do
      Timecop.freeze(Time.new(2026, 5, 11, 10, 0, 0)) do
        post "/plans", title: "첫 평가", period: "daily", plan_date: "2026-05-11", body: ""
        expect(last_response.status).to eq(302)
      end
      Timecop.freeze(Time.new(2026, 5, 11, 15, 0, 0)) do
        post "/plans", title: "새 평가", period: "daily", plan_date: "2026-05-11", body: ""
        # 사용자 보고 버그: 두 번째 POST 가 500 났음. v0.1.7 hotfix 가 한 row 만 유지했고,
        # W32 부터 두 row 모두 유지.
        expect(last_response.status).to eq(302)
      end

      expect(db[:entries].where(mode: "plan").count).to eq(2)
    end
  end

  describe "오전/오후 grouping (GET /plans)" do
    before do
      Timecop.freeze(Time.new(2026, 5, 11, 9, 30, 0)) do
        Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
          .call(title: "🌅 오전 1", period: :daily, plan_date: "2026-05-11")
      end
      Timecop.freeze(Time.new(2026, 5, 11, 10, 15, 0)) do
        Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
          .call(title: "🌅 오전 2", period: :daily, plan_date: "2026-05-11")
      end
      Timecop.freeze(Time.new(2026, 5, 11, 14, 0, 0)) do
        Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
          .call(title: "🌆 오후 1", period: :daily, plan_date: "2026-05-11")
      end
    end

    it "오전 2건 + 오후 1건 — 모두 표시" do
      get "/plans?period=daily"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("🌅 오전 1")
      expect(last_response.body).to include("🌅 오전 2")
      expect(last_response.body).to include("🌆 오후 1")
    end

    it "🌅 오전 / 🌆 오후 헤더 분리" do
      get "/plans?period=daily"
      expect(last_response.body).to match(/🌅 오전 <small>\(2건\)/)
      expect(last_response.body).to match(/🌆 오후 <small>\(1건\)/)
    end

    it "날짜 헤더 + 총 건수" do
      get "/plans?period=daily"
      expect(last_response.body).to match(/2026-05-11[^<]*<small>\(총 3건/)
    end

    it "오전·오후 카드 색상 분리 (CSS class)" do
      get "/plans?period=daily"
      expect(last_response.body).to include("plans__half-day--morning")
      expect(last_response.body).to include("plans__half-day--afternoon")
    end

    it "오전 plan 안에 오후 plan 안 들어감 (순서 유지)" do
      get "/plans?period=daily"
      body = last_response.body

      morning_idx = body.index("🌅 오전 <small>")
      afternoon_idx = body.index("🌆 오후 <small>")

      morning_plan_1_idx = body.index("🌅 오전 1")
      afternoon_plan_idx = body.index("🌆 오후 1")

      expect(morning_idx).to be < afternoon_idx
      expect(morning_idx).to be < morning_plan_1_idx
      expect(morning_plan_1_idx).to be < afternoon_idx
    end
  end

  describe "다른 날짜 plan 도 별도 그룹" do
    it "두 날짜 → 두 group 분리" do
      Timecop.freeze(Time.new(2026, 5, 11, 10, 0, 0)) do
        Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
          .call(title: "11일", period: :daily, plan_date: "2026-05-11")
      end
      Timecop.freeze(Time.new(2026, 5, 12, 10, 0, 0)) do
        Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
          .call(title: "12일", period: :daily, plan_date: "2026-05-12")
      end

      get "/plans?period=daily"
      # 두 group 모두 노출
      expect(last_response.body).to include("2026-05-11")
      expect(last_response.body).to include("2026-05-12")
      # 최근 날짜 (12일) 가 먼저 (역순)
      idx_12 = last_response.body.index("2026-05-12")
      idx_11 = last_response.body.index("2026-05-11")
      expect(idx_12).to be < idx_11
    end
  end

  describe "project/semester — grouping 없이 단일 리스트" do
    it "?period=project → date group 없음, 단일 list" do
      Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "프로젝트 A", period: :project, plan_date: "book-write")

      get "/plans?period=project"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("프로젝트 A")
      # date-group 헤더는 없어야 함 (시간 grouping 의미 약함)
      expect(last_response.body).not_to include("plans__half-day--morning")
    end
  end
end
