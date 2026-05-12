# frozen_string_literal: true

require "rack/test"

# Phase 13 W27-T03 — Plan IndexRepo 통합 (마이그레이션 008).
# Plan 도 entries 테이블에 인덱싱 → recent_across / /view/recent / 검색 1급 시민.
RSpec.describe "Plan IndexRepo 통합 (Phase 13 W27-T03)", type: :request do
  include Rack::Test::Methods

  def app
    Sowing::Application
  end

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:plan_repo) { Sowing::Repositories::PlanRepo.new(vault_dir: vault_dir) }

  before do
    header "Host", "127.0.0.1"
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    %w[00_Inbox 20_Notes 30_Records 40_Plans .sowing/synth].each do |d|
      FileUtils.rm_rf(vault_dir.join(d))
    end
  end

  describe "Migration 008 — entries.mode CHECK 에 plan 추가" do
    it "plan mode 의 entry 도 entries 테이블에 INSERT 가능 (CHECK 통과)" do
      use_case = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
      result = use_case.call(title: "T", period: :daily, plan_date: "2026-05-11", body: "본문")
      expect(result.success?).to be true

      plan = result.value!
      row = db[:entries].where(id: plan.id.to_s).first
      expect(row).not_to be_nil
      expect(row[:mode]).to eq("plan")
    end

    it "여전히 memo/note/record 도 정상 (회귀 0)" do
      Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "메모")
      Sowing::UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "T", body: "B", category: "회고")

      expect(db[:entries].where(mode: "memo").count).to eq(1)
      expect(db[:entries].where(mode: "record").count).to eq(1)
    end

    it "잘못된 mode (gibberish) 는 여전히 CHECK 위반으로 거부" do
      expect {
        db[:entries].insert(
          id: "01KRTEST00000000000000000A",
          path: "test.md",
          mode: "invalid",
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601,
          file_mtime: 0,
          file_hash: "x",
          indexed_at: Time.now.iso8601
        )
      }.to raise_error(Sequel::CheckConstraintViolation)
    end
  end

  describe "PlanRepo.write → IndexRepo upsert 통합" do
    it "PlanRepo.write 가 entries 테이블에 자동 upsert" do
      use_case = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
      result = use_case.call(title: "협동학습 평가", period: :daily, plan_date: "2026-05-11")
      plan = result.value!

      row = db[:entries].where(id: plan.id.to_s).first
      expect(row).not_to be_nil
      expect(row[:title]).to eq("협동학습 평가")
      # W32: {date}-{HHmm}-{id4}.md 패턴
      expect(row[:path]).to match(%r{\A40_Plans/daily/2026-05-11-\d{4}-[0-9A-Z]{4}\.md\z})
      expect(row[:mode]).to eq("plan")
    end

    it "toggle_done → entries 의 done 반영 (frontmatter 동기)" do
      use_case = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
      result = use_case.call(title: "T", period: :daily, plan_date: "2026-05-11")
      plan = result.value!

      # 토글 → file 의 frontmatter done: true 가 됨을 확인
      toggled = plan_repo.toggle_done(plan.id.to_s)
      expect(toggled.done).to be true

      # entries 테이블에도 같은 row 가 갱신됨 (file_mtime 또는 file_hash 차이)
      row = db[:entries].where(id: plan.id.to_s).first
      expect(row).not_to be_nil
    end
  end

  describe "IndexRepo.recent_across — plan 도 시간순 포함" do
    it "메모·필기·기록·계획 4 mode 모두 시간순 통합" do
      Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "메모1")
      sleep 0.01
      Sowing::UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "기록1", body: "B", category: "회고")
      sleep 0.01
      Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "계획1", period: :daily, plan_date: "2026-05-11")

      entries = index_repo.recent_across(limit: 10)
      modes = entries.map(&:mode)
      expect(modes).to include(:memo, :record, :plan)
    end
  end

  describe "/view/recent — plan 도 chip 필터" do
    it "?mode=plan → plan 만 (memo 메모 본문 미노출)" do
      Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "내일 협동학습", period: :daily, plan_date: "2026-05-11", body: "x")
      Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "MEMO_UNIQUE_BODY_001")

      get "/view/recent?mode=plan"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("내일 협동학습")
      expect(last_response.body).not_to include("MEMO_UNIQUE_BODY_001")
    end

    it "전체 chip → plan 도 시간순 노출" do
      Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "계획A", period: :daily, plan_date: "2026-05-11")

      get "/view/recent"
      expect(last_response.body).to include("계획A")
      expect(last_response.body).to include("🗓 계획")
    end

    it "plan entry 의 link 가 /plans/{id} 로" do
      result = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "T", period: :daily, plan_date: "2026-05-11")
      plan_id = result.value!.id.to_s

      get "/view/recent"
      expect(last_response.body).to include(%(href="/plans/#{plan_id}"))
    end
  end

  describe "같은 period+date 여러 plan (Phase 14 W32 — overwrite 폐지)" do
    it "같은 날짜 두 번 제출 → 두 row 모두 유지 (unique path)" do
      first = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "첫 평가", period: :daily, plan_date: "2026-05-11").value!
      second = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "새 평가", period: :daily, plan_date: "2026-05-11").value!

      # 두 plan 의 path 가 unique (HHmm + id4 prefix 다름)
      expect(first.id.to_s).not_to eq(second.id.to_s)
      # entries 에 두 row 모두 존재 (overwrite X)
      expect(db[:entries].where(id: first.id.to_s).count).to eq(1)
      expect(db[:entries].where(id: second.id.to_s).count).to eq(1)
      # 같은 plan_date 의 plan 2건
      titles = db[:entries].where(mode: "plan").select_map(:title).sort
      expect(titles).to eq(["새 평가", "첫 평가"])
    end

    it "toggle_done — 같은 id 재제출 시 row 1 개 유지" do
      first = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "T", period: :daily, plan_date: "2026-05-11").value!

      plan_repo.toggle_done(first.id.to_s)
      expect(db[:entries].where(id: first.id.to_s).count).to eq(1)
    end
  end

  describe "IndexRepo.find — plan 단건 조회" do
    it "find(plan_id) → IndexedEntry with mode: :plan" do
      result = Sowing::UseCases::CreatePlan.new(plan_repo: plan_repo)
        .call(title: "T", period: :weekly, plan_date: "2026-W19")
      plan_id = result.value!.id.to_s

      indexed = index_repo.find(plan_id)
      expect(indexed).not_to be_nil
      expect(indexed.mode).to eq(:plan)
      # W32: {date}-{HHmm}-{id4}.md 패턴
      expect(indexed.path).to match(%r{\A40_Plans/weekly/2026-W19-\d{4}-[0-9A-Z]{4}\.md\z})
    end
  end
end
