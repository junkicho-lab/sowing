# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Phase R Stage 2 R2-T02 — Capture::ItemRepo (Item 영속화 어댑터).
RSpec.describe Sowing::Capture::ItemRepo do
  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("capture-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:repo) { described_class.new(vault_repo: vault_repo, index_repo: index_repo) }

  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:other_ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZJ") }
  let(:created_at) { Time.new(2026, 5, 12, 9, 23, 14, "+09:00") }

  before do
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete
  end

  after do
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  def build_item(id: ulid, body: "본문", subject: nil, **opts)
    Sowing::Capture::Item.new(
      id: id, body: body, created_at: created_at, subject: subject, **opts
    )
  end

  describe "#create" do
    it "Item 을 받아 그대로 반환 (불변)" do
      item = build_item
      result = repo.create(item)
      expect(result).to equal(item)
    end

    it "00_Inbox/ 에 마크다운 파일 생성" do
      repo.create(build_item)
      expect(vault_dir.join("00_Inbox/2026-05-12_092314.md")).to exist
    end

    it "entries 테이블에 mode='memo' 로 인덱싱" do
      repo.create(build_item)
      row = db[:entries].where(id: ulid.to_s).first
      expect(row).not_to be_nil
      expect(row[:mode]).to eq("memo")
      expect(row[:path]).to eq("00_Inbox/2026-05-12_092314.md")
    end

    it "subject 포함 Item 의 frontmatter 에 subject 키 작성" do
      repo.create(build_item(subject: :person))
      content = vault_dir.join("00_Inbox/2026-05-12_092314.md").read
      expect(content).to include("subject: person")
    end

    it "Item 이 아닌 객체는 ArgumentError" do
      memo = Sowing::Domain::Memo.new(id: ulid, body: "x", created_at: created_at)
      expect { repo.create(memo) }.to raise_error(ArgumentError, /Capture::Item/)
    end
  end

  describe "#find" do
    context "subject 없는 Item" do
      it "저장 후 같은 id 로 round-trip" do
        repo.create(build_item)
        found = repo.find(ulid)
        expect(found).to be_a(Sowing::Capture::Item)
        expect(found.id).to eq(ulid)
        expect(found.body).to eq("본문")
        expect(found.subject).to be_nil
      end
    end

    context "subject 있는 Item" do
      it "frontmatter 에서 subject 를 Symbol 로 복원" do
        repo.create(build_item(subject: :document))
        found = repo.find(ulid)
        expect(found.subject).to eq(:document)
      end

      Sowing::Capture::Item::SUBJECTS.each do |axis|
        it "subject: #{axis.inspect} 라운드트립" do
          repo.create(build_item(subject: axis))
          expect(repo.find(ulid).subject).to eq(axis)
        end
      end
    end

    it "존재하지 않는 id 는 nil" do
      expect(repo.find(ulid)).to be_nil
    end

    it "mode 가 memo 가 아닌 entry 는 nil (다른 BC 영역 격리)" do
      # 직접 IndexRepo 에 note 를 넣어두고 ItemRepo.find 호출
      note = Sowing::Domain::Note.new(
        id: ulid, body: "필기", created_at: created_at, category: "lessons", title: "테스트"
      )
      note_path = vault_repo.write(note)
      index_repo.upsert(
        note,
        path: note_path.relative_path_from(vault_dir).to_s,
        file_mtime: note_path.mtime.to_i,
        file_hash: vault_repo.file_hash(note_path),
        word_count: 1
      )
      expect(repo.find(ulid)).to be_nil
    end
  end

  describe "#recent" do
    let(:t1) { Time.new(2026, 5, 12, 9, 0, 0, "+09:00") }
    let(:t2) { Time.new(2026, 5, 12, 10, 0, 0, "+09:00") }
    let(:t3) { Time.new(2026, 5, 12, 11, 0, 0, "+09:00") }
    let(:id1) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ611") }
    let(:id2) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ622") }
    let(:id3) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ633") }

    before do
      repo.create(Sowing::Capture::Item.new(id: id1, body: "첫째", created_at: t1, subject: :person))
      repo.create(Sowing::Capture::Item.new(id: id2, body: "둘째", created_at: t2, subject: :subject))
      repo.create(Sowing::Capture::Item.new(id: id3, body: "셋째", created_at: t3))
    end

    it "최신순으로 반환 (created_at desc)" do
      result = repo.recent(limit: 10)
      expect(result.map(&:body)).to eq(["셋째", "둘째", "첫째"])
    end

    it "limit 적용" do
      expect(repo.recent(limit: 2).size).to eq(2)
    end

    it "각 결과는 Capture::Item 이며 subject 복원" do
      result = repo.recent(limit: 10)
      expect(result).to all(be_a(Sowing::Capture::Item))
      expect(result.map(&:subject)).to eq([nil, :subject, :person])
    end
  end
end
