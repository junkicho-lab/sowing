# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::DeleteSamples do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("delete-samples-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Core::DB.connection }
  let(:use_case) { described_class.new(vault_repo: vault_repo, index_repo: index_repo) }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  def seed_samples
    Sowing::UseCases::SeedSamples.new(vault_repo: vault_repo, index_repo: index_repo).call.value!
  end

  def create_real_entry
    Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
      title: "내가 만든 진짜 필기", body: "본문",
      category: "lessons", source: "교과서"
    ).value!
  end

  describe "#call" do
    it "샘플 시드 후 → 12건 모두 휴지통으로 이동 + 인덱스에서 제거" do
      seed_samples
      expect(db[:entries].count).to eq(12)

      result = use_case.call

      expect(result).to be_success
      expect(result.value!).to eq(12)
      expect(index_repo.find_samples).to be_empty
      expect(db[:entries].count).to eq(0)

      trashed = Dir.glob(vault_dir.join(".sowing/trash/**/*.md"))
      expect(trashed.size).to eq(12)
    end

    it "사용자가 만든 entry는 보존 (sample prefix 아니면 건드리지 않음)" do
      seed_samples
      real_note = create_real_entry

      use_case.call

      expect(index_repo.find(real_note.id)).not_to be_nil
      expect(db[:entries].count).to eq(1)
    end

    it "샘플이 없으면 Success(0)" do
      result = use_case.call
      expect(result.value!).to eq(0)
    end

    it "파일이 외부에서 미리 사라진 경우에도 인덱스 정리 (graceful)" do
      seed_samples
      first = index_repo.find_samples.first
      File.unlink(vault_dir.join(first[:path])) # 외부 삭제 시뮬레이션

      result = use_case.call
      expect(result).to be_success
      expect(result.value!).to eq(12) # 인덱스 12건 모두 정리
    end
  end
end
