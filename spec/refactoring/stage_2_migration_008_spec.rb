# frozen_string_literal: true

# Phase R Stage 2 R2-T05 — Migration 008 (entries.subject 컬럼 + 4축 CHECK).
RSpec.describe "Migration 008 — entries.subject (Stage 2 R2-T05)" do
  let(:db) { Sowing::Core::DB.connection }

  describe "스키마" do
    it "entries 테이블에 subject TEXT 컬럼 존재" do
      schema = db.schema(:entries).to_h
      expect(schema).to have_key(:subject)
      expect(schema[:subject][:db_type]).to eq("TEXT")
      expect(schema[:subject][:allow_null]).to be(true)
    end

    it "subject 인덱스 존재 (filter·검색 성능)" do
      indexes = db.indexes(:entries)
      expect(indexes.values.any? { |info| info[:columns] == [:subject] }).to be(true)
    end

    it "CHECK 제약: 4축 외 String 거부" do
      expect {
        db[:entries].insert(
          id: "01KR1FE1QYH4EEP6RAGR9D008", path: "x.md", mode: "memo",
          subject: "random_axis",
          created_at: Time.now.iso8601, updated_at: Time.now.iso8601,
          file_mtime: Time.now.to_i, file_hash: "abc", word_count: 0,
          indexed_at: Time.now.iso8601
        )
      }.to raise_error(Sequel::CheckConstraintViolation)
    end

    it "CHECK 제약: 4축 String 허용" do
      Sowing::Capture::Item::SUBJECTS.each_with_index do |axis, i|
        ulid_str = "01KR1FE1QYH4EEP6RAGR9D00#{i}"
        expect {
          db[:entries].insert(
            id: ulid_str, path: "x#{i}.md", mode: "memo",
            subject: axis.to_s,
            created_at: Time.now.iso8601, updated_at: Time.now.iso8601,
            file_mtime: Time.now.to_i, file_hash: "abc", word_count: 0,
            indexed_at: Time.now.iso8601
          )
        }.not_to raise_error
      end
    end

    it "CHECK 제약: NULL 허용 (분류 안 한 capture)" do
      expect {
        db[:entries].insert(
          id: "01KR1FE1QYH4EEP6RAGR9D0NL", path: "null.md", mode: "memo",
          subject: nil,
          created_at: Time.now.iso8601, updated_at: Time.now.iso8601,
          file_mtime: Time.now.to_i, file_hash: "abc", word_count: 0,
          indexed_at: Time.now.iso8601
        )
      }.not_to raise_error
    end
  end

  describe "IndexRepo 통합" do
    let(:repo) { Sowing::Repositories::IndexRepo.new }
    let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: Sowing::Core::Paths.vault_dir) }
    let(:created_at) { Time.new(2026, 5, 12, 9, 0, 0, "+09:00") }

    before do
      db[:links].delete
      db[:entry_tags].delete
      db[:tags].delete
      db[:entries_fts].delete
      db[:entries].delete
    end

    it "Item 의 subject 가 entries.subject 에 String 으로 인덱싱됨" do
      item = Sowing::Capture::Item.new(
        id: Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9D0PER"),
        body: "본문", created_at: created_at, subject: :person
      )
      abs = vault_repo.write(item)
      repo.upsert(
        item,
        path: abs.relative_path_from(vault_repo.vault_dir).to_s,
        file_mtime: abs.mtime.to_i,
        file_hash: vault_repo.file_hash(abs),
        word_count: 1
      )

      row = db[:entries].where(id: item.id.to_s).first
      expect(row[:subject]).to eq("person")
    end

    it "subject 없는 Memo 도 동일 경로로 nil 저장 (호환)" do
      memo = Sowing::Domain::Memo.new(
        id: Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9D0MEM"),
        body: "본문", created_at: created_at
      )
      abs = vault_repo.write(memo)
      repo.upsert(
        memo,
        path: abs.relative_path_from(vault_repo.vault_dir).to_s,
        file_mtime: abs.mtime.to_i,
        file_hash: vault_repo.file_hash(abs),
        word_count: 1
      )

      row = db[:entries].where(id: memo.id.to_s).first
      expect(row[:subject]).to be_nil
    end

    it "IndexedEntry.subject 가 Symbol 로 복원 (DB String → Sym)" do
      item = Sowing::Capture::Item.new(
        id: Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9D0SBJ"),
        body: "본문", created_at: created_at, subject: :subject
      )
      abs = vault_repo.write(item)
      indexed = repo.upsert(
        item,
        path: abs.relative_path_from(vault_repo.vault_dir).to_s,
        file_mtime: abs.mtime.to_i,
        file_hash: vault_repo.file_hash(abs),
        word_count: 1
      )

      expect(indexed.subject).to eq(:subject)
      expect(repo.find(item.id).subject).to eq(:subject)
    end

    it "IndexedEntry.subject 가 nil 인 경우도 round-trip" do
      memo = Sowing::Domain::Memo.new(
        id: Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9D0N0N"),
        body: "본문", created_at: created_at
      )
      abs = vault_repo.write(memo)
      indexed = repo.upsert(
        memo,
        path: abs.relative_path_from(vault_repo.vault_dir).to_s,
        file_mtime: abs.mtime.to_i,
        file_hash: vault_repo.file_hash(abs),
        word_count: 1
      )

      expect(indexed.subject).to be_nil
    end
  end
end
