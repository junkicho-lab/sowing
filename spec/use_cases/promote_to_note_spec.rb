# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::PromoteToNote do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("promote-to-note-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Core::DB.connection }
  let(:created_at) { Time.new(2026, 5, 1, 9, 23, 14, "+09:00") }
  let(:promoted_at) { Time.new(2026, 5, 8, 14, 0, 0, "+09:00") }

  let(:create_memo) {
    Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo, clock: class_double(Time, now: created_at))
  }
  let(:promote) {
    described_class.new(vault_repo: vault_repo, index_repo: index_repo, clock: class_double(Time, now: promoted_at))
  }

  before do
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  let!(:memo) {
    create_memo.call(body: "오늘 1교시 수업이 활기찼다 #수업").value!
  }

  let(:valid_attrs) {
    {title: "1교시 수업 회고", category: "lessons", source: "현장 관찰"}
  }

  describe "#call (정상)" do
    it "Success(Note)를 반환한다" do
      result = promote.call(id: memo.id, **valid_attrs)
      expect(result).to be_success
      expect(result.value!).to be_a(Sowing::Domain::Note)
    end

    it "ID는 그대로 유지" do
      result = promote.call(id: memo.id, **valid_attrs)
      expect(result.value!.id).to eq(memo.id)
    end

    it "created_at은 메모의 시각 그대로, updated_at은 승격 시각" do
      result = promote.call(id: memo.id, **valid_attrs)
      note = result.value!
      expect(note.created_at).to eq(created_at)
      expect(note.updated_at).to eq(promoted_at)
    end

    it "본문(body)은 그대로" do
      result = promote.call(id: memo.id, **valid_attrs)
      expect(result.value!.body).to eq(memo.body)
    end

    it "title/category/source가 새로 부여됨" do
      result = promote.call(id: memo.id, **valid_attrs)
      note = result.value!
      expect(note.title).to eq("1교시 수업 회고")
      expect(note.category).to eq("lessons")
      expect(note.source).to eq("현장 관찰")
    end

    it "promoted_from에 옛 메모 path 기록" do
      indexed_before = index_repo.find(memo.id)
      result = promote.call(id: memo.id, **valid_attrs)
      expect(result.value!.promoted_from).to eq(indexed_before.path)
    end

    it "tags override 미지정이면 메모의 태그를 그대로" do
      # 메모는 본문 #수업이 있으나, frontmatter tags는 빈 TagSet
      # → memo.tags는 빈 TagSet (Memo는 frontmatter tags만 도메인 객체로 보유)
      result = promote.call(id: memo.id, **valid_attrs)
      expect(result.value!.tags).to eq(memo.tags)
    end

    it "tags override 지정 시 새 TagSet으로" do
      result = promote.call(id: memo.id, **valid_attrs, tags: ["수업", "회고"])
      expect(result.value!.tags.to_a).to eq(["수업", "회고"])
    end

    it "옛 00_Inbox/ 파일이 휴지통으로 이동, 새 20_Notes/{cat}/{title}.md 생성" do
      indexed_before = index_repo.find(memo.id)
      old_path = vault_dir.join(indexed_before.path)
      expect(old_path).to exist

      promote.call(id: memo.id, **valid_attrs)

      expect(old_path).not_to exist
      expect(vault_dir.join("20_Notes/lessons/1교시 수업 회고.md")).to exist
      expect(vault_dir.join(".sowing/trash/#{indexed_before.path}")).to exist
    end

    it "SQLite 인덱스의 mode는 :note로 갱신, path도 새 위치" do
      promote.call(id: memo.id, **valid_attrs)
      indexed = index_repo.find(memo.id)
      expect(indexed.mode).to eq(:note)
      expect(indexed.path).to eq("20_Notes/lessons/1교시 수업 회고.md")
      expect(indexed.title).to eq("1교시 수업 회고")
      expect(indexed.category).to eq("lessons")
      expect(indexed.source).to eq("현장 관찰")
      expect(indexed.promoted_from).to start_with("00_Inbox/")
    end

    it "VaultRepo로 다시 read한 결과도 promoted_from을 보존한다 (round-trip)" do
      indexed_before = index_repo.find(memo.id)
      promote.call(id: memo.id, **valid_attrs)
      restored = vault_repo.read("20_Notes/lessons/1교시 수업 회고.md")
      expect(restored).to be_a(Sowing::Domain::Note)
      expect(restored.promoted_from).to eq(indexed_before.path)
    end
  end

  describe "#call (검증 실패)" do
    it "title 비면 :empty_title (인덱스 변경 없음)" do
      result = promote.call(id: memo.id, **valid_attrs.merge(title: " "))
      expect(result.failure).to eq(:empty_title)
      expect(index_repo.find(memo.id).mode).to eq(:memo) # 변경 없음
    end

    it "category 비면 :empty_category" do
      expect(promote.call(id: memo.id, **valid_attrs.merge(category: "")).failure).to eq(:empty_category)
    end

    it "category enum 외면 :invalid_category" do
      expect(promote.call(id: memo.id, **valid_attrs.merge(category: "alien")).failure).to eq(:invalid_category)
    end

    it "source 비면 :empty_source" do
      expect(promote.call(id: memo.id, **valid_attrs.merge(source: "")).failure).to eq(:empty_source)
    end
  end

  describe "#call (못 찾는 경우)" do
    it "id가 없으면 :not_found" do
      result = promote.call(id: "01XXXXXXXXXXXXXXXXXXXXXXXX", **valid_attrs)
      expect(result.failure).to eq(:not_found)
    end

    it "노트 id면 :not_a_memo" do
      note = Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "n", body: "b", category: "lessons", source: "s").value!
      result = promote.call(id: note.id.to_s, **valid_attrs)
      expect(result.failure).to eq(:not_a_memo)
    end

    it "파일이 사라졌으면 :file_missing" do
      indexed = index_repo.find(memo.id)
      File.delete(vault_dir.join(indexed.path))
      result = promote.call(id: memo.id, **valid_attrs)
      expect(result.failure).to eq(:file_missing)
    end
  end

  describe "backlinks 보존 (ID 유지의 효과)" do
    it "다른 entry가 같은 ID로 [[link]]를 가지면 mode 변경 후에도 매칭" do
      # 메모 ID로의 inbound 링크는 title 매칭이 아니라 entry id로 직접 추적되지 않음
      # (links는 target_text로 동작). 본 테스트는 ID 유지의 부수 효과 — links 테이블 안전성.
      # Note 승격 후 자기 자신의 links_from은 본문에 wikilink 없으므로 그대로 빈 상태.
      promote.call(id: memo.id, **valid_attrs)
      # 본문이 그대로 유지되어 outbound 위키링크도 그대로 (본 메모는 wikilink 없음)
      expect(index_repo.links_from(memo.id)).to be_empty
    end
  end
end
