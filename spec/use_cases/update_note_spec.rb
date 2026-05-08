# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::UpdateNote do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("update-note-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:created_at) { Time.new(2026, 5, 1, 9, 0, 0, "+09:00") }
  let(:updated_at) { Time.new(2026, 5, 8, 14, 30, 0, "+09:00") }
  let(:clock) { class_double(Time, now: updated_at) }

  let(:create_note) {
    Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo, clock: class_double(Time, now: created_at))
  }
  let(:update_note) {
    described_class.new(vault_repo: vault_repo, index_repo: index_repo, clock: clock)
  }

  before do
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after do
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  let(:original_attrs) {
    {
      title: "원본",
      body: "원본 본문",
      category: "lessons",
      source: "교과서 1단원"
    }
  }

  let!(:original) {
    create_note.call(**original_attrs).value!
  }

  describe "#call (정상 update)" do
    it "Success(Note)를 반환한다" do
      result = update_note.call(id: original.id, **original_attrs.merge(title: "수정된 제목"))
      expect(result).to be_success
      expect(result.value!.title).to eq("수정된 제목")
    end

    it "id, created_at은 불변이다" do
      result = update_note.call(id: original.id, **original_attrs.merge(title: "수정"))
      note = result.value!
      expect(note.id).to eq(original.id)
      expect(note.created_at).to eq(original.created_at)
    end

    it "updated_at은 clock.now로 갱신된다" do
      result = update_note.call(id: original.id, **original_attrs.merge(body: "수정 본문"))
      expect(result.value!.updated_at).to eq(updated_at)
    end

    it "tags가 정규화되어 인덱스에 반영된다" do
      update_note.call(id: original.id, **original_attrs.merge(tags: ["연수", "복습"]))
      indexed = index_repo.find(original.id)
      expect(indexed.tags).to eq(["복습", "연수"])
    end

    context "title 변경 (path 변경)" do
      it "옛 파일은 휴지통으로, 새 파일이 새 path에 생긴다" do
        old_path = vault_dir.join("20_Notes/lessons/원본.md")
        expect(old_path).to exist

        update_note.call(id: original.id, **original_attrs.merge(title: "새 제목"))

        expect(old_path).not_to exist
        expect(vault_dir.join("20_Notes/lessons/새 제목.md")).to exist
        expect(vault_dir.join(".sowing/trash/20_Notes/lessons/원본.md")).to exist
      end

      it "인덱스의 path 컬럼도 새 path로 갱신된다" do
        update_note.call(id: original.id, **original_attrs.merge(title: "새 제목"))
        indexed = index_repo.find(original.id)
        expect(indexed.path).to eq("20_Notes/lessons/새 제목.md")
      end
    end

    context "category 변경 (디렉토리 변경)" do
      it "새 카테고리 디렉토리에 쓰고 옛 디렉토리 파일은 휴지통으로" do
        update_note.call(id: original.id, **original_attrs.merge(category: "trainings"))

        expect(vault_dir.join("20_Notes/trainings/원본.md")).to exist
        expect(vault_dir.join("20_Notes/lessons/원본.md")).not_to exist
        expect(vault_dir.join(".sowing/trash/20_Notes/lessons/원본.md")).to exist
      end
    end

    context "title·category 모두 그대로 (overwrite)" do
      it "같은 path에 덮어쓰고 휴지통 항목 없음" do
        update_note.call(id: original.id, **original_attrs.merge(body: "본문만 수정"))

        expect(vault_dir.join("20_Notes/lessons/원본.md").read).to include("본문만 수정")
        expect(vault_dir.join(".sowing/trash").exist?).to be false
      end
    end
  end

  describe "#call (실패)" do
    it "id가 없으면 :not_found" do
      result = update_note.call(id: "01XXXXXXXXXXXXXXXXXXXXXXXX", **original_attrs)
      expect(result.failure).to eq(:not_found)
    end

    it "다른 mode의 entry id면 :not_found" do
      memo = Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo).call(body: "메모").value!
      result = update_note.call(id: memo.id.to_s, **original_attrs)
      expect(result.failure).to eq(:not_found)
    end

    it "파일이 사라졌으면 :file_missing" do
      File.delete(vault_dir.join("20_Notes/lessons/원본.md"))
      result = update_note.call(id: original.id, **original_attrs)
      expect(result.failure).to eq(:file_missing)
    end

    it "title 비어 있으면 :empty_title" do
      result = update_note.call(id: original.id, **original_attrs.merge(title: ""))
      expect(result.failure).to eq(:empty_title)
    end

    it "category enum 외면 :invalid_category" do
      result = update_note.call(id: original.id, **original_attrs.merge(category: "alien"))
      expect(result.failure).to eq(:invalid_category)
    end

    it "source 비어 있으면 :empty_source" do
      result = update_note.call(id: original.id, **original_attrs.merge(source: ""))
      expect(result.failure).to eq(:empty_source)
    end
  end
end
