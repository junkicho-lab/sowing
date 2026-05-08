# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::ReindexEntry do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("reindex-entry-spec-")) }
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

  def create_note_via_use_case(title: "원본 제목", body: "원본 본문", category: "lessons")
    Sowing::UseCases::CreateNote.new(
      vault_repo: vault_repo,
      index_repo: index_repo
    ).call(title: title, body: body, category: category, source: "교과서").value!
  end

  def event(type, path)
    {type: type, path: Pathname.new(path.to_s)}
  end

  describe ":modified — 외부 에디터로 본문 수정" do
    let(:note) { create_note_via_use_case }
    let(:abs_path) { vault_dir.join(index_repo.find(note.id).path) }

    it "파일을 다시 읽어 인덱스를 갱신 + Success(:reindexed)" do
      File.write(abs_path, abs_path.read.sub("원본 본문", "외부에서 수정한 본문"))
      sleep 1.1 # mtime 변경 보장 (POSIX는 1초 단위 mtime)

      result = use_case.call(event(:modified, abs_path))

      expect(result).to be_success
      expect(result.value!).to eq(:reindexed)
      reindexed = index_repo.find(note.id)
      expect(reindexed.file_mtime).to eq(abs_path.mtime.to_i)
      expect(reindexed.word_count).to eq(3) # "외부에서 수정한 본문" → 3 words (whitespace split)
    end

    it "mtime·hash가 그대로면 :unchanged — 인덱스 작업 스킵" do
      result = use_case.call(event(:modified, abs_path))
      expect(result).to be_success
      expect(result.value!).to eq(:unchanged)
    end

    it "title이 바뀌어도 path가 같으면 인덱스만 갱신 (path 컬럼 보존)" do
      content = abs_path.read.sub("title: 원본 제목", "title: 외부에서 바꾼 제목")
      File.write(abs_path, content)
      sleep 1.1

      use_case.call(event(:modified, abs_path))
      reindexed = index_repo.find(note.id)
      expect(reindexed.title).to eq("외부에서 바꾼 제목")
    end
  end

  describe ":added — 인덱스에 없던 새 파일" do
    it "frontmatter 정상이면 Success(:added)" do
      note = create_note_via_use_case(title: "신규 필기")
      old_path = vault_dir.join(index_repo.find(note.id).path)
      # 인덱스에서만 제거 (파일은 유지) — :added 시뮬레이션
      index_repo.delete(note.id)

      result = use_case.call(event(:added, old_path))
      expect(result).to be_success
      expect(result.value!).to eq(:added)
      expect(index_repo.find(note.id)).not_to be_nil
    end

    it "frontmatter 누락(adoption 필요)은 Failure(:invalid_frontmatter)" do
      orphan = vault_dir.join("00_Inbox/orphan.md")
      FileUtils.mkdir_p(orphan.dirname)
      File.write(orphan, "프론트매터 없는 외부 파일")

      result = use_case.call(event(:added, orphan))
      expect(result).to be_failure
      expect(result.failure.first).to eq(:invalid_frontmatter)
    end
  end

  describe ":removed — 외부에서 파일 삭제" do
    it "인덱스에서 row 제거 + Success(:removed)" do
      note = create_note_via_use_case
      abs_path = vault_dir.join(index_repo.find(note.id).path)

      File.unlink(abs_path)
      result = use_case.call(event(:removed, abs_path))

      expect(result).to be_success
      expect(result.value!).to eq(:removed)
      expect(index_repo.find(note.id)).to be_nil
    end

    it "인덱스에 없던 path면 Success(:not_indexed)" do
      result = use_case.call(event(:removed, vault_dir.join("phantom.md")))
      expect(result).to be_success
      expect(result.value!).to eq(:not_indexed)
    end
  end

  describe "엣지 케이스" do
    it "파일이 사라진 :modified는 Failure(:file_missing)" do
      result = use_case.call(event(:modified, vault_dir.join("ghost.md")))
      expect(result).to be_failure
      expect(result.failure).to eq(:file_missing)
    end

    it "알 수 없는 type은 Failure(:unknown_event_type)" do
      result = use_case.call({type: :weird, path: vault_dir.join("x.md")})
      expect(result).to be_failure
      expect(result.failure).to eq(:unknown_event_type)
    end
  end
end
