# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::PromoteToRecord do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("promote-to-record-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:created_at) { Time.new(2026, 5, 1, 9, 0, 0, "+09:00") }
  let(:promoted_at) { Time.new(2026, 5, 8, 15, 0, 0, "+09:00") }

  let(:create_memo) {
    Sowing::UseCases::CreateMemo.new(
      vault_repo: vault_repo, index_repo: index_repo,
      clock: class_double(Time, now: created_at)
    )
  }
  let(:create_note) {
    Sowing::UseCases::CreateNote.new(
      vault_repo: vault_repo, index_repo: index_repo,
      clock: class_double(Time, now: created_at)
    )
  }
  let(:promote) {
    described_class.new(
      vault_repo: vault_repo, index_repo: index_repo,
      clock: class_double(Time, now: promoted_at)
    )
  }

  before do
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  describe "메모 → 기록 승격" do
    let!(:memo) { create_memo.call(body: "오늘 #수업 활기").value! }
    let(:valid_attrs) { {title: "5월 수업 회고", category: "학급운영"} }

    it "Success(Record)를 반환한다" do
      result = promote.call(id: memo.id, **valid_attrs)
      expect(result).to be_success
      expect(result.value!).to be_a(Sowing::Domain::Record)
    end

    it "ID·created_at·body 유지, updated_at은 promoted_at" do
      result = promote.call(id: memo.id, **valid_attrs)
      record = result.value!
      expect(record.id).to eq(memo.id)
      expect(record.created_at).to eq(created_at)
      expect(record.updated_at).to eq(promoted_at)
      expect(record.body).to eq(memo.body)
    end

    it "promoted_from에 옛 메모 path 기록" do
      indexed_before = index_repo.find(memo.id)
      result = promote.call(id: memo.id, **valid_attrs)
      expect(result.value!.promoted_from).to eq(indexed_before.path)
    end

    it "옛 메모 → 휴지통, 새 30_Records 생성" do
      indexed_before = index_repo.find(memo.id)
      promote.call(id: memo.id, **valid_attrs)

      year = created_at.strftime("%Y")
      expect(vault_dir.join(indexed_before.path)).not_to exist
      expect(vault_dir.join("30_Records/#{year}/학급운영/5월 수업 회고.md")).to exist
      expect(vault_dir.join(".sowing/trash/#{indexed_before.path}")).to exist
    end

    it "인덱스 mode가 :record로 갱신" do
      promote.call(id: memo.id, **valid_attrs)
      expect(index_repo.find(memo.id).mode).to eq(:record)
    end
  end

  describe "필기 → 기록 승격" do
    let!(:note) {
      create_note.call(
        title: "협동학습 정리",
        body: "협동학습은 ...",
        category: "trainings",
        source: "2026 봄 연수",
        tags: ["연수"]
      ).value!
    }
    let(:valid_attrs) { {title: "협동학습 — 영구 보관본", category: "수업철학"} }

    it "필기도 source로 허용 (mode: :note)" do
      result = promote.call(id: note.id, **valid_attrs)
      expect(result).to be_success
    end

    it "필기의 ID·body·tags 유지" do
      result = promote.call(id: note.id, **valid_attrs)
      record = result.value!
      expect(record.id).to eq(note.id)
      expect(record.body).to eq(note.body)
      expect(record.tags).to eq(note.tags)
    end

    it "옛 필기는 휴지통, 새 30_Records 디렉토리 생성" do
      promote.call(id: note.id, **valid_attrs)
      year = created_at.strftime("%Y")
      expect(vault_dir.join("20_Notes/trainings/협동학습 정리.md")).not_to exist
      expect(vault_dir.join("30_Records/#{year}/수업철학/협동학습 — 영구 보관본.md")).to exist
      expect(vault_dir.join(".sowing/trash/20_Notes/trainings/협동학습 정리.md")).to exist
    end

    it "promoted_from에 옛 필기 path 기록 + 인덱스도 동기화" do
      indexed_before = index_repo.find(note.id)
      promote.call(id: note.id, **valid_attrs)
      indexed = index_repo.find(note.id)
      expect(indexed.mode).to eq(:record)
      expect(indexed.promoted_from).to eq(indexed_before.path)
    end
  end

  describe "검증 실패" do
    let!(:memo) { create_memo.call(body: "본문").value! }

    it "title 비면 :empty_title" do
      expect(promote.call(id: memo.id, title: "", category: "X").failure).to eq(:empty_title)
    end

    it "category 비면 :empty_category" do
      expect(promote.call(id: memo.id, title: "T", category: " ").failure).to eq(:empty_category)
    end

    it "category는 자유 텍스트 — 임의 한글 허용" do
      expect(promote.call(id: memo.id, title: "T", category: "독립 카테고리")).to be_success
    end
  end

  describe "찾지 못함" do
    it "id가 없으면 :not_found" do
      expect(promote.call(id: "01XXXXXXXXXXXXXXXXXXXXXXXX", title: "T", category: "X").failure)
        .to eq(:not_found)
    end

    it "이미 record면 :not_promotable" do
      record = Sowing::UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "원본 기록", body: "본문", category: "X").value!
      expect(promote.call(id: record.id.to_s, title: "T", category: "X").failure)
        .to eq(:not_promotable)
    end

    it "파일 누락 시 :file_missing" do
      memo = create_memo.call(body: "본문").value!
      indexed = index_repo.find(memo.id)
      File.delete(vault_dir.join(indexed.path))
      expect(promote.call(id: memo.id, title: "T", category: "X").failure)
        .to eq(:file_missing)
    end
  end

  describe "tags override" do
    let!(:memo) { create_memo.call(body: "본문").value! }

    it "nil이면 source의 태그 유지" do
      result = promote.call(id: memo.id, title: "T", category: "X")
      expect(result.value!.tags).to eq(memo.tags)
    end

    it "지정하면 새 TagSet" do
      result = promote.call(id: memo.id, title: "T", category: "X", tags: ["수업"])
      expect(result.value!.tags.to_a).to eq(["수업"])
    end
  end
end
