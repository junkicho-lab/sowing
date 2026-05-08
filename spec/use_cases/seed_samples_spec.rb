# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::SeedSamples do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("seed-samples-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:use_case) { described_class.new(vault_repo: vault_repo, index_repo: index_repo) }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  describe "#call — 기본 시드" do
    it "12건 모두 시드 + Success({seeded: 12, skipped: 0, total: 12})" do
      result = use_case.call
      expect(result).to be_success
      data = result.value!
      expect(data[:seeded]).to eq(12)
      expect(data[:skipped]).to eq(0)
      expect(data[:total]).to eq(12)
    end

    it "vault에 12개 마크다운 파일 작성됨 (mode별 위치 분배)" do
      use_case.call
      expect(Dir.glob(vault_dir.join("00_Inbox/*.md")).size).to eq(4)  # memos
      expect(Dir.glob(vault_dir.join("20_Notes/**/*.md")).size).to eq(4)  # notes
      expect(Dir.glob(vault_dir.join("30_Records/**/*.md")).size).to eq(4)  # records
    end

    it "인덱스에도 12건 등록 (mode별)" do
      use_case.call
      expect(index_repo.count(mode: :memo)).to eq(4)
      expect(index_repo.count(mode: :note)).to eq(4)
      expect(index_repo.count(mode: :record)).to eq(4)
    end

    it "위키링크 그래프 형성 — broken link가 자동 re-link됨" do
      use_case.call
      total_links = db[:links].count
      broken = db[:links].where(target_id: nil).count
      expect(total_links).to be >= 3
      expect(broken).to eq(0), "broken link #{broken}건 — 샘플 위키링크 타겟 매칭 실패"
    end

    it "태그가 자동 인덱싱됨 (frontmatter + 본문 #태그 합집합)" do
      use_case.call
      tags = db[:tags].select_map(:name)
      expect(tags).to include("협동학습", "학생관찰", "수업", "회고")
    end
  end

  describe "중복 시드 방지 (ROADMAP 검증 항목)" do
    it "이미 시드된 상태에서 재호출 → 모두 skipped" do
      use_case.call
      result2 = use_case.call

      data = result2.value!
      expect(data[:seeded]).to eq(0)
      expect(data[:skipped]).to eq(12)
      # 파일 수도 그대로 (덮어쓰기 없음)
      expect(Dir.glob(vault_dir.join("**/*.md")).size).to eq(12)
    end

    it "일부만 시드된 상태에서는 누락분만 채움" do
      # 1개 entry를 미리 직접 시드
      sample = Sowing::Domain::Memo.new(
        id: Sowing::Domain::ValueObjects::Ulid.parse("01KR1SAMP00000000000000001"),
        body: "이미 있음",
        created_at: Time.now,
        tags: Sowing::Domain::ValueObjects::TagSet.new([])
      )
      abs = vault_repo.write(sample)
      index_repo.upsert(sample,
        path: abs.relative_path_from(vault_dir).to_s,
        file_mtime: abs.mtime.to_i,
        file_hash: "deadbeef00000000")

      result = use_case.call
      data = result.value!
      expect(data[:seeded]).to eq(11)
      expect(data[:skipped]).to eq(1)
    end
  end

  describe "엣지 케이스" do
    it "samples_dir이 없으면 Failure(:samples_dir_missing)" do
      uc = described_class.new(vault_repo: vault_repo, index_repo: index_repo, samples_dir: "/nonexistent")
      result = uc.call
      expect(result).to be_failure
      expect(result.failure).to eq(:samples_dir_missing)
    end

    it "빈 samples_dir은 Success(0/0/0) — 파일이 없을 뿐 에러 아님" do
      empty_dir = Dir.mktmpdir("empty-samples-")
      uc = described_class.new(vault_repo: vault_repo, index_repo: index_repo, samples_dir: empty_dir)
      result = uc.call
      expect(result.value!).to eq(seeded: 0, skipped: 0, total: 0)
      FileUtils.rm_rf(empty_dir)
    end
  end
end
