# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Phase R Stage 3 R3-T05 — Archive 메타 (migration 009, ADR-017).
RSpec.describe "Knowledge Archive (Stage 3 R3-T05)" do
  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("archive-spec-")) }
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
    Sowing::Knowledge.index_repo = index_repo
  end

  after do
    Sowing::Knowledge.reset_repos!
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  describe "Migration 009 — 스키마" do
    it "entries 에 archived_at + archive_reason 컬럼 존재" do
      schema = db.schema(:entries).to_h
      expect(schema).to have_key(:archived_at)
      expect(schema).to have_key(:archive_reason)
      expect(schema[:archived_at][:db_type]).to eq("TEXT")
    end

    it "archived_at 에 인덱스 존재" do
      indexes = db.indexes(:entries)
      expect(indexes.values.any? { |info| info[:columns] == [:archived_at] }).to be(true)
    end

    it "기본값은 NULL (활성 entry)" do
      record = Sowing::Knowledge.create_record(title: "t", body: "b", category: "c")
      row = db[:entries].where(id: record.id.to_s).first
      expect(row[:archived_at]).to be_nil
      expect(row[:archive_reason]).to be_nil
    end
  end

  describe "Knowledge.archive" do
    let(:record) {
      Sowing::Knowledge.create_record(title: "졸업생 김OO", body: "본문", category: "students")
    }

    it "성공 시 true 반환" do
      expect(Sowing::Knowledge.archive(record.id, reason: "2026년 졸업")).to be(true)
    end

    it "DB 에 archived_at ISO8601 + archive_reason 기록" do
      Sowing::Knowledge.archive(record.id, reason: "2026년 졸업")
      row = db[:entries].where(id: record.id.to_s).first
      expect(row[:archived_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(row[:archive_reason]).to eq("2026년 졸업")
    end

    it "존재하지 않는 id 는 false" do
      bogus = "01KR1FE1QYH4EEP6RAGR9DJ6ZH"
      expect(Sowing::Knowledge.archive(bogus, reason: "test")).to be(false)
    end

    it "reason 빈 문자열 → ArgumentError" do
      expect { Sowing::Knowledge.archive(record.id, reason: "") }
        .to raise_error(ArgumentError, /reason/)
    end
  end

  describe "Knowledge.unarchive" do
    let(:record) {
      Sowing::Knowledge.create_record(title: "잘못 보관", body: "본문", category: "x")
    }

    before { Sowing::Knowledge.archive(record.id, reason: "실수") }

    it "보관 해제 후 archived_at = NULL" do
      Sowing::Knowledge.unarchive(record.id)
      row = db[:entries].where(id: record.id.to_s).first
      expect(row[:archived_at]).to be_nil
      expect(row[:archive_reason]).to be_nil
    end
  end

  describe "IndexRepo.list — 기본 archived 제외 (일상 회상)" do
    let(:active) {
      Sowing::Knowledge.create_record(title: "활성", body: "b", category: "c",
        created_at: Time.new(2026, 5, 12, 9, 0, 0))
    }
    let(:archived) {
      Sowing::Knowledge.create_record(title: "보관", body: "b", category: "c",
        created_at: Time.new(2026, 5, 12, 10, 0, 0))
    }

    before do
      active
      archived
      Sowing::Knowledge.archive(archived.id, reason: "졸업")
    end

    it "기본 list 는 archived 제외" do
      result = index_repo.list(mode: :record)
      expect(result.size).to eq(1)
      expect(result.first.id).to eq(active.id.to_s)
    end

    it "include_archived: true 로 포함" do
      result = index_repo.list(mode: :record, include_archived: true)
      expect(result.size).to eq(2)
    end

    it "Knowledge.recent_records 도 archived 제외 (Façade 일관성)" do
      result = Sowing::Knowledge.recent_records(limit: 10)
      expect(result.size).to eq(1)
      expect(result.first.title).to eq("활성")
    end
  end

  describe "Knowledge.archived — 보관함 조회" do
    before do
      r1 = Sowing::Knowledge.create_record(title: "A", body: "b", category: "c",
        created_at: Time.new(2026, 5, 12, 9))
      r2 = Sowing::Knowledge.create_record(title: "B", body: "b", category: "c",
        created_at: Time.new(2026, 5, 12, 10))
      Sowing::Knowledge.create_record(title: "활성", body: "b", category: "c") # 보관 안 함
      Sowing::Knowledge.archive(r1.id, reason: "졸업1")
      Sowing::Knowledge.archive(r2.id, reason: "졸업2")
    end

    it "보관된 entry 만 반환 (활성 제외)" do
      result = Sowing::Knowledge.archived(mode: :record)
      expect(result.size).to eq(2)
      expect(result.map(&:title)).to contain_exactly("A", "B")
    end

    it "archived_at desc 정렬 (최근 보관이 위)" do
      result = Sowing::Knowledge.archived(mode: :record)
      expect(result.first.archive_reason).to eq("졸업2")
      expect(result.last.archive_reason).to eq("졸업1")
    end
  end

  describe "IndexedEntry#archived?" do
    it "archived_at 있으면 true" do
      r = Sowing::Knowledge.create_record(title: "x", body: "y", category: "c")
      Sowing::Knowledge.archive(r.id, reason: "test")
      indexed = index_repo.find(r.id)
      expect(indexed.archived?).to be(true)
      expect(indexed.archived_at).to be_a(Time)
      expect(indexed.archive_reason).to eq("test")
    end

    it "archived_at 없으면 false" do
      r = Sowing::Knowledge.create_record(title: "x", body: "y", category: "c")
      indexed = index_repo.find(r.id)
      expect(indexed.archived?).to be(false)
    end
  end
end
