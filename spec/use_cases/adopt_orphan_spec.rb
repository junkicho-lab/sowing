# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::AdoptOrphan do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("adopt-orphan-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 5, 8, 14, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  let(:use_case) { described_class.new(vault_repo: vault_repo, index_repo: index_repo, clock: clock) }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  def write_orphan(rel_path, content)
    abs = vault_dir.join(rel_path)
    FileUtils.mkdir_p(abs.dirname)
    File.write(abs, content)
    abs
  end

  def event(path)
    {type: :added, path: Pathname.new(path.to_s)}
  end

  describe "mode 추론 (경로 기반)" do
    it "00_Inbox/foo.md → memo" do
      abs = write_orphan("00_Inbox/orphan.md", "외부 메모 본문")
      result = use_case.call(event(abs))
      expect(result).to be_success
      expect(result.value!.mode).to eq(:memo)
    end

    it "20_Notes/lessons/foo.md → note (category=lessons)" do
      abs = write_orphan("20_Notes/lessons/외부필기.md", "# 외부 제목\n\n본문")
      result = use_case.call(event(abs))
      expect(result).to be_success
      note = result.value!
      expect(note.mode).to eq(:note)
      expect(note.category).to eq("lessons")
      expect(note.source).to eq("외부")
    end

    it "30_Records/2026/학급운영/foo.md → record (category=학급운영)" do
      abs = write_orphan("30_Records/2026/학급운영/회고.md", "기록 본문")
      result = use_case.call(event(abs))
      expect(result).to be_success
      record = result.value!
      expect(record.mode).to eq(:record)
      expect(record.category).to eq("학급운영")
    end

    it "20_Notes/foo.md (category 누락) → Failure(:unsupported_path)" do
      abs = write_orphan("20_Notes/loose.md", "본문")
      expect(use_case.call(event(abs)).failure).to eq(:unsupported_path)
    end

    it "vault root 파일은 Failure(:unsupported_path)" do
      abs = write_orphan("misplaced.md", "어디에도 안 맞음")
      expect(use_case.call(event(abs)).failure).to eq(:unsupported_path)
    end
  end

  describe "title 추출" do
    it "본문 첫 H1을 title로 사용 + 본문에서 제거" do
      abs = write_orphan("20_Notes/lessons/file.md", "# 진짜 제목\n\n실제 본문")
      result = use_case.call(event(abs))
      note = result.value!
      expect(note.title).to eq("진짜 제목")
      expect(note.body).to eq("실제 본문")
    end

    it "H1 없으면 파일명 (확장자 제외)" do
      abs = write_orphan("20_Notes/lessons/대체제목.md", "본문만 있는 파일")
      result = use_case.call(event(abs))
      expect(result.value!.title).to eq("대체제목")
      expect(result.value!.body).to eq("본문만 있는 파일")
    end
  end

  describe "frontmatter in-place 기록" do
    let!(:abs) { write_orphan("00_Inbox/inplace.md", "메모 본문") }

    before { use_case.call(event(abs)) }

    it "원본 위치에 frontmatter가 prepend된다 (path 보존)" do
      content = abs.read
      expect(content).to start_with("---\n")
      expect(content).to include("mode: memo")
      expect(content).to include("메모 본문")
    end

    it "재파싱 가능 — 두 번째 호출은 :not_orphan" do
      result2 = use_case.call(event(abs))
      expect(result2).to be_failure
      expect(result2.failure).to eq(:not_orphan)
    end

    it "VaultRepo.read로 다시 로드 가능 (round-trip)" do
      reloaded = vault_repo.read(abs)
      expect(reloaded.mode).to eq(:memo)
      expect(reloaded.body).to eq("메모 본문")
    end
  end

  describe "인덱스 등록" do
    it "adoption 후 IndexRepo에서 조회 가능 (path·mode 일치)" do
      abs = write_orphan("20_Notes/lessons/idx.md", "# 인덱스 테스트\n\n본문")
      result = use_case.call(event(abs))
      indexed = index_repo.find(result.value!.id)
      expect(indexed).not_to be_nil
      expect(indexed.path).to eq("20_Notes/lessons/idx.md")
      expect(indexed.mode).to eq(:note)
      expect(indexed.title).to eq("인덱스 테스트")
    end
  end

  describe "엣지 케이스" do
    it "이미 frontmatter가 있는 파일은 Failure(:not_orphan) — 방어적" do
      abs = write_orphan("00_Inbox/with_fm.md", "---\nid: 01XYZ\nmode: memo\n---\n\n본문")
      expect(use_case.call(event(abs)).failure).to eq(:not_orphan)
    end

    it "파일 사라진 경우 Failure(:file_missing)" do
      result = use_case.call(event(vault_dir.join("00_Inbox/ghost.md")))
      expect(result).to be_failure
      expect(result.failure).to eq(:file_missing)
    end
  end

  describe "Coordinator 통합 — invalid_frontmatter fallback" do
    let(:coordinator) do
      Sowing::Sync::Coordinator.new(
        vault_dir: vault_dir, vault_repo: vault_repo, index_repo: index_repo
      )
    end

    it "ReindexEntry가 :invalid_frontmatter면 AdoptOrphan으로 폴백 → Success(:adopted)" do
      abs = write_orphan("00_Inbox/coordinated.md", "코디네이터 흐름")
      result = coordinator.handle_event(type: :added, path: abs)
      expect(result).to be_success
      expect(result.value!).to eq(:adopted)
      expect(abs.read).to start_with("---\n")
    end

    it "adoption_enabled: false면 폴백 안 함 — :invalid_frontmatter 유지" do
      coord = Sowing::Sync::Coordinator.new(
        vault_dir: vault_dir, vault_repo: vault_repo, index_repo: index_repo,
        adoption_enabled: false
      )
      abs = write_orphan("00_Inbox/no_adopt.md", "입양 끔")
      result = coord.handle_event(type: :added, path: abs)
      expect(result).to be_failure
      expect(result.failure.first).to eq(:invalid_frontmatter)
    end
  end
end
