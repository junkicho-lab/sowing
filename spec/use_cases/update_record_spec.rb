# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::UpdateRecord do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("update-record-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:created_at) { Time.new(2026, 5, 1, 0, 0, 0, "+09:00") }
  let(:updated_at) { Time.new(2026, 5, 8, 14, 0, 0, "+09:00") }

  let(:create_use_case) {
    Sowing::UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo, clock: class_double(Time, now: created_at))
  }
  let(:update_use_case) {
    described_class.new(vault_repo: vault_repo, index_repo: index_repo, clock: class_double(Time, now: updated_at))
  }

  let(:original_attrs) { {title: "원본", body: "원본 본문", category: "학급운영"} }

  before do
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  # cleanup 이후에 fixture 생성 (let!의 실행 순서를 before와 분리).
  let!(:original) { create_use_case.call(**original_attrs).value! }

  describe "#call (정상)" do
    it "id, created_at은 불변이고 updated_at은 갱신" do
      result = update_use_case.call(id: original.id, **original_attrs.merge(body: "수정"))
      expect(result).to be_success
      record = result.value!
      expect(record.id).to eq(original.id)
      expect(record.created_at).to eq(created_at)
      expect(record.updated_at).to eq(updated_at)
    end

    it "category 변경 시 새 디렉토리에 쓰고 옛 파일은 휴지통으로" do
      update_use_case.call(id: original.id, **original_attrs.merge(category: "수업철학"))

      expect(vault_dir.join("30_Records/2026/수업철학/원본.md")).to exist
      expect(vault_dir.join("30_Records/2026/학급운영/원본.md")).not_to exist
      expect(vault_dir.join(".sowing/trash/30_Records/2026/학급운영/원본.md")).to exist
    end

    it "title 변경 시 같은 디렉토리 내 새 path + 옛 파일 휴지통" do
      update_use_case.call(id: original.id, **original_attrs.merge(title: "수정된 제목"))

      expect(vault_dir.join("30_Records/2026/학급운영/수정된 제목.md")).to exist
      expect(vault_dir.join(".sowing/trash/30_Records/2026/학급운영/원본.md")).to exist
    end

    it "promoted_from 추가 가능" do
      result = update_use_case.call(id: original.id, **original_attrs.merge(promoted_from: "00_Inbox/x.md"))
      indexed = index_repo.find(result.value!.id)
      expect(indexed.promoted_from).to eq("00_Inbox/x.md")
    end

    it "title/category 동일하면 atomic 덮어쓰기 (휴지통 비어있음)" do
      update_use_case.call(id: original.id, **original_attrs.merge(body: "본문만"))
      expect(vault_dir.join(".sowing/trash").exist?).to be false
    end
  end

  describe "#call (실패)" do
    it "id가 없으면 :not_found" do
      result = update_use_case.call(id: "01XXXXXXXXXXXXXXXXXXXXXXXX", **original_attrs)
      expect(result.failure).to eq(:not_found)
    end

    it "다른 mode의 id면 :not_found (Note id로 접근)" do
      note = Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "n", body: "b", category: "lessons", source: "s").value!
      result = update_use_case.call(id: note.id.to_s, **original_attrs)
      expect(result.failure).to eq(:not_found)
    end

    it "파일이 사라지면 :file_missing" do
      File.delete(vault_dir.join("30_Records/2026/학급운영/원본.md"))
      result = update_use_case.call(id: original.id, **original_attrs)
      expect(result.failure).to eq(:file_missing)
    end

    it "title/body/category 비면 각각 :empty_*" do
      expect(update_use_case.call(id: original.id, **original_attrs.merge(title: "")).failure).to eq(:empty_title)
      expect(update_use_case.call(id: original.id, **original_attrs.merge(body: "")).failure).to eq(:empty_body)
      expect(update_use_case.call(id: original.id, **original_attrs.merge(category: "")).failure).to eq(:empty_category)
    end
  end
end
