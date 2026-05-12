# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Phase R Stage 3 R3-T03~T04 — Knowledge Façade + Repo 통합.
RSpec.describe "Sowing::Knowledge Façade (Stage 3 R3-T03~T04)" do
  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("knowledge-facade-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }

  before do
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete
    Sowing::Knowledge.record_repo = Sowing::Knowledge::RecordRepo.new(
      vault_repo: vault_repo, index_repo: index_repo
    )
    Sowing::Knowledge.plan_repo = Sowing::Knowledge::PlanRepo.new(
      vault_dir: vault_dir, index_repo: index_repo
    )
  end

  after do
    Sowing::Knowledge.reset_repos!
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  describe ".create_record" do
    it "필수 인자 (title·body·category) 로 Record 생성·저장" do
      record = Sowing::Knowledge.create_record(
        title: "1단원 정리", body: "본문 내용", category: "lessons"
      )
      expect(record).to be_a(Sowing::Knowledge::Record)
      expect(record.title).to eq("1단원 정리")
      expect(record.category).to eq("lessons")
    end

    it "30_Records/{YYYY}/{category}/ 에 파일 생성" do
      Sowing::Knowledge.create_record(
        title: "회고", body: "본문", category: "학급운영",
        created_at: Time.new(2026, 5, 12, 9, 0, 0)
      )
      expect(vault_dir.join("30_Records/2026/학급운영/회고.md")).to exist
    end

    it "entries 테이블에 mode='record' 로 인덱싱" do
      record = Sowing::Knowledge.create_record(
        title: "x", body: "y", category: "lessons"
      )
      row = db[:entries].where(id: record.id.to_s).first
      expect(row[:mode]).to eq("record")
      expect(row[:category]).to eq("lessons")
    end

    it "source 부착 (옛 Note 흡수)" do
      record = Sowing::Knowledge.create_record(
        title: "참고서 정리", body: "본문", category: "books",
        source: "수업혁명 p.42"
      )
      expect(record.source).to eq("수업혁명 p.42")
    end

    it "subject 4축 부착" do
      record = Sowing::Knowledge.create_record(
        title: "학생 관찰", body: "본문", category: "students",
        subject: :person
      )
      expect(record.subject).to eq(:person)
      row = db[:entries].where(id: record.id.to_s).first
      expect(row[:subject]).to eq("person")
    end

    it "title 빈 문자열 → ArgumentError" do
      expect {
        Sowing::Knowledge.create_record(title: "", body: "본문", category: "x")
      }.to raise_error(ArgumentError, /title/)
    end

    it "body 빈 문자열 → ArgumentError" do
      expect {
        Sowing::Knowledge.create_record(title: "t", body: "", category: "x")
      }.to raise_error(ArgumentError, /body/)
    end

    it "category 빈 문자열 → ArgumentError" do
      expect {
        Sowing::Knowledge.create_record(title: "t", body: "본문", category: "")
      }.to raise_error(ArgumentError, /category/)
    end
  end

  describe ".create_plan" do
    it "필수 인자로 Plan 생성·저장" do
      plan = Sowing::Knowledge.create_plan(
        title: "1교시 준비", period: :daily, plan_date: "2026-05-12"
      )
      expect(plan).to be_a(Sowing::Knowledge::Plan)
      expect(plan.period).to eq(:daily)
    end

    it "40_Plans/{period}/ 에 파일 생성" do
      plan = Sowing::Knowledge.create_plan(
        title: "주간계획", period: :weekly, plan_date: "2026-W19",
        created_at: Time.new(2026, 5, 12, 9, 30, 0)
      )
      glob = Dir.glob(vault_dir.join("40_Plans/weekly/2026-W19-*.md"))
      expect(glob.size).to eq(1)
    end

    it "entries 테이블에 mode='plan' 으로 인덱싱" do
      plan = Sowing::Knowledge.create_plan(
        title: "x", period: :daily, plan_date: "2026-05-12"
      )
      row = db[:entries].where(id: plan.id.to_s).first
      expect(row[:mode]).to eq("plan")
    end

    it "subject 부착" do
      plan = Sowing::Knowledge.create_plan(
        title: "x", period: :daily, plan_date: "2026-05-12", subject: :document
      )
      expect(plan.subject).to eq(:document)
    end

    it "title 빈 → ArgumentError" do
      expect {
        Sowing::Knowledge.create_plan(title: "", period: :daily, plan_date: "2026-05-12")
      }.to raise_error(ArgumentError, /title/)
    end

    it "period 4축 밖이면 (Plan validation) ArgumentError" do
      expect {
        Sowing::Knowledge.create_plan(title: "x", period: :random, plan_date: "2026-05-12")
      }.to raise_error(ArgumentError, /period/)
    end
  end

  describe ".find" do
    it "Record id 로 회수" do
      r = Sowing::Knowledge.create_record(title: "t", body: "b", category: "c", subject: :subject)
      found = Sowing::Knowledge.find(r.id)
      expect(found).to be_a(Sowing::Knowledge::Record)
      expect(found.subject).to eq(:subject)
    end

    it "Plan id 로 회수" do
      p = Sowing::Knowledge.create_plan(title: "x", period: :daily, plan_date: "2026-05-12")
      found = Sowing::Knowledge.find(p.id)
      expect(found).to be_a(Sowing::Knowledge::Plan)
    end

    it "존재하지 않으면 nil" do
      bogus = Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH")
      expect(Sowing::Knowledge.find(bogus)).to be_nil
    end
  end

  describe ".recent_records / .recent_plans 격리" do
    before do
      Sowing::Knowledge.create_record(title: "r1", body: "b", category: "c",
        created_at: Time.new(2026, 5, 12, 9))
      Sowing::Knowledge.create_record(title: "r2", body: "b", category: "c",
        created_at: Time.new(2026, 5, 12, 10))
      Sowing::Knowledge.create_plan(title: "p1", period: :daily, plan_date: "2026-05-12",
        created_at: Time.new(2026, 5, 12, 11))
    end

    it "recent_records 는 Plan 제외" do
      result = Sowing::Knowledge.recent_records(limit: 10)
      expect(result).to all(be_a(Sowing::Knowledge::Record))
      expect(result.size).to eq(2)
      expect(result.map(&:title)).to eq(["r2", "r1"]) # created_at desc
    end

    it "recent_plans 는 Record 제외" do
      result = Sowing::Knowledge.recent_plans(limit: 10)
      expect(result).to all(be_a(Sowing::Knowledge::Plan))
      expect(result.size).to eq(1)
    end
  end

  describe "archive / unarchive (R3-T05 stub)" do
    it "archive 호출 시 NotImplementedError + ADR-017 안내" do
      expect { Sowing::Knowledge.archive("x", reason: "졸업") }
        .to raise_error(NotImplementedError, /ADR-017/)
    end
  end
end
