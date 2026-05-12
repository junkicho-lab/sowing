# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::Sync::ConsistencyCheck do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("consistency-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Core::DB.connection }
  let(:coordinator) do
    Sowing::Sync::Coordinator.new(
      vault_dir: vault_dir, vault_repo: vault_repo, index_repo: index_repo
    )
  end
  let(:check) do
    described_class.new(vault_dir: vault_dir, index_repo: index_repo, coordinator: coordinator)
  end

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  def create_note(title: "테스트")
    Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
      title: title, body: "본문", category: "lessons", source: "교과서"
    ).value!
  end

  describe "#run — 4가지 일관성 케이스" do
    it "디스크·인덱스 일치하면 unchanged 카운트" do
      create_note(title: "일관됨")
      summary = check.run
      expect(summary.unchanged).to eq(1)
      expect(summary.reindexed).to eq(0)
      expect(summary.removed).to eq(0)
    end

    it "인덱스만 비웠다가 부팅 → 모두 :added로 재구축 (인덱스 삭제 후 자동 재구축)" do
      create_note(title: "재구축 대상 1")
      create_note(title: "재구축 대상 2")
      # 인덱스 wipe — 파일은 그대로
      db[:entries_fts].delete
      db[:links].delete
      db[:entry_tags].delete
      db[:tags].delete
      db[:entries].delete

      summary = check.run

      expect(summary.added).to eq(2)
      expect(index_repo.all_paths.size).to eq(2)
    end

    it "디스크에서 파일 삭제 → :removed로 인덱스에서도 제거" do
      note = create_note(title: "사라질 파일")
      abs = vault_dir.join(index_repo.find(note.id).path)
      File.unlink(abs)

      summary = check.run

      expect(summary.removed).to eq(1)
      expect(index_repo.find(note.id)).to be_nil
    end

    it "외부에서 본문만 수정 → :reindexed" do
      note = create_note(title: "수정될 파일")
      abs = vault_dir.join(index_repo.find(note.id).path)
      File.write(abs, abs.read.sub("본문", "외부에서 수정한 본문"))
      sleep 1.1 # mtime 1초 단위 보장

      summary = check.run

      expect(summary.reindexed).to eq(1)
    end
  end

  describe "외부 신규 파일(adoption)" do
    it "frontmatter 없는 .md → :adopted (Coordinator 폴백)" do
      orphan = vault_dir.join("00_Inbox/orphan.md")
      FileUtils.mkdir_p(orphan.dirname)
      File.write(orphan, "외부에서 만든 메모")

      summary = check.run

      expect(summary.adopted).to eq(1)
      expect(orphan.read).to start_with("---\n")
    end
  end

  describe ".sowing 디렉토리 무시" do
    it "휴지통 등 .sowing/ 하위 .md는 스캔 대상 아님" do
      trash = vault_dir.join(".sowing/trash/old.md")
      FileUtils.mkdir_p(trash.dirname)
      File.write(trash, "휴지통 내용")

      summary = check.run

      expect(summary.total).to eq(0)
    end
  end

  describe "Summary" do
    it "to_h 키 + total 합계" do
      create_note(title: "한건")
      summary = check.run
      h = summary.to_h
      expect(h.keys).to contain_exactly(:unchanged, :reindexed, :added, :adopted, :removed, :not_indexed, :errors)
      expect(summary.total).to eq(1)
    end
  end

  describe "복합 시나리오" do
    it "한 번에 unchanged + reindexed + removed + adopted 모두 처리" do
      kept = create_note(title: "유지")
      modified = create_note(title: "수정됨")
      deleted = create_note(title: "삭제됨")

      mod_abs = vault_dir.join(index_repo.find(modified.id).path)
      File.write(mod_abs, mod_abs.read.sub("본문", "수정됨"))
      sleep 1.1

      del_abs = vault_dir.join(index_repo.find(deleted.id).path)
      File.unlink(del_abs)

      orphan = vault_dir.join("00_Inbox/외부.md")
      FileUtils.mkdir_p(orphan.dirname)
      File.write(orphan, "외부 메모")

      summary = check.run

      expect(summary.unchanged).to eq(1)
      expect(summary.reindexed).to eq(1)
      expect(summary.removed).to eq(1)
      expect(summary.adopted).to eq(1)
      expect(index_repo.find(kept.id)).not_to be_nil
      expect(index_repo.find(deleted.id)).to be_nil
    end
  end
end
