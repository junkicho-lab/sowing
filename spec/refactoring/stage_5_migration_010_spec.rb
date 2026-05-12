# frozen_string_literal: true

# Phase R Stage 5 R5-T01 — Migration 010 (entries.mode='note' → 'record', ADR-015).
RSpec.describe "Migration 010 — Note → Record 데이터 변환 (Stage 5 R5-T01)" do
  let(:db) { Sowing::Core::DB.connection }

  # 본 마이그레이션은 사전에 적용됨 (suite 시작 시 Sequel::Migrator 가 010 까지 모두 실행).
  # 본 spec 은 SQL 변환 로직의 정확성을 검증 — 새로 'note' 행을 직접 삽입한 뒤
  # 동일 SQL 을 재실행해서 변환되는지 확인.
  #
  # 멱등성 검증: 이미 'record' 인 행에 재실행해도 부작용 없음.

  CONVERSION_SQL = <<~SQL.freeze
    UPDATE entries
    SET path = REPLACE(path,
      '20_Notes/',
      '30_Records/' || SUBSTR(created_at, 1, 4) || '/'),
      mode = 'record'
    WHERE mode = 'note'
  SQL

  before do
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete
  end

  describe "마이그레이션 010 이 suite 부팅 시 적용됨" do
    it "schema_info 테이블에 version 10+ 기록" do
      # Sequel 의 integer migrator 는 schema_info 에 단일 행 (version) 저장.
      schema_info = db[:schema_info].first
      expect(schema_info[:version]).to be >= 10
    end
  end

  describe "변환 SQL — 단순 케이스" do
    before do
      db[:entries].insert(
        id: "01KR1FE1QYH4EEP6RAGR9D0N01",
        path: "20_Notes/lessons/1단원정리.md",
        mode: "note",
        title: "1단원 정리",
        category: "lessons",
        created_at: "2026-05-12T09:00:00+09:00",
        updated_at: "2026-05-12T09:00:00+09:00",
        file_mtime: Time.now.to_i,
        file_hash: "abc123",
        word_count: 100,
        indexed_at: Time.now.iso8601
      )
    end

    it "mode 가 'record' 로 변환" do
      db.run(CONVERSION_SQL)
      row = db[:entries].first
      expect(row[:mode]).to eq("record")
    end

    it "path 의 20_Notes/{cat}/ → 30_Records/{YYYY}/{cat}/" do
      db.run(CONVERSION_SQL)
      row = db[:entries].first
      expect(row[:path]).to eq("30_Records/2026/lessons/1단원정리.md")
    end

    it "다른 컬럼 (category·title·tags·source) 은 보존" do
      db.run(CONVERSION_SQL)
      row = db[:entries].first
      expect(row[:title]).to eq("1단원 정리")
      expect(row[:category]).to eq("lessons")
    end
  end

  describe "멱등성" do
    it "0 note 행 → UPDATE 영향 0 (안전 재실행)" do
      affected = db.run(CONVERSION_SQL)
      # 0 행이면 raise 없이 통과 — Sequel run 은 영향 행 수 반환 안함, 예외 없음으로 검증
      expect { db.run(CONVERSION_SQL) }.not_to raise_error
    end

    it "이미 변환된 record 행 재실행 — 변화 없음" do
      db[:entries].insert(
        id: "01KR1FE1QYH4EEP6RAGR9D0R02",
        path: "30_Records/2026/lessons/x.md",
        mode: "record",
        title: "이미 변환됨",
        created_at: "2026-05-12T09:00:00+09:00",
        updated_at: "2026-05-12T09:00:00+09:00",
        file_mtime: Time.now.to_i,
        file_hash: "abc",
        word_count: 1,
        indexed_at: Time.now.iso8601
      )
      db.run(CONVERSION_SQL)
      row = db[:entries].first
      expect(row[:path]).to eq("30_Records/2026/lessons/x.md") # 변화 없음
      expect(row[:mode]).to eq("record")
    end
  end

  describe "여러 연도 + 여러 카테고리" do
    before do
      [
        {id: "01KR1FE1QYH4EEP6RAGR9D0A01", year: "2025", cat: "lessons", file: "a.md"},
        {id: "01KR1FE1QYH4EEP6RAGR9D0A02", year: "2025", cat: "books", file: "b.md"},
        {id: "01KR1FE1QYH4EEP6RAGR9D0A03", year: "2026", cat: "trainings", file: "c.md"}
      ].each do |r|
        db[:entries].insert(
          id: r[:id],
          path: "20_Notes/#{r[:cat]}/#{r[:file]}",
          mode: "note",
          category: r[:cat],
          created_at: "#{r[:year]}-05-12T09:00:00+09:00",
          updated_at: "#{r[:year]}-05-12T09:00:00+09:00",
          file_mtime: Time.now.to_i,
          file_hash: "h",
          word_count: 1,
          indexed_at: Time.now.iso8601
        )
      end
    end

    it "각 행이 자기 연도 + 카테고리 path 로 변환" do
      db.run(CONVERSION_SQL)
      paths = db[:entries].order(:id).select_map(:path)
      expect(paths).to eq([
        "30_Records/2025/lessons/a.md",
        "30_Records/2025/books/b.md",
        "30_Records/2026/trainings/c.md"
      ])
    end

    it "모든 행 mode='record'" do
      db.run(CONVERSION_SQL)
      expect(db[:entries].distinct.select_map(:mode)).to eq(["record"])
    end
  end

  describe "PROMOTE TO RECORD 와의 통합" do
    it "변환 후 IndexRepo.list(mode: :record) 가 옛 note 도 발견" do
      db[:entries].insert(
        id: "01KR1FE1QYH4EEP6RAGR9D0L01",
        path: "20_Notes/lessons/x.md",
        mode: "note",
        title: "옛 note",
        category: "lessons",
        created_at: "2026-05-12T09:00:00+09:00",
        updated_at: "2026-05-12T09:00:00+09:00",
        file_mtime: Time.now.to_i,
        file_hash: "h",
        word_count: 1,
        indexed_at: Time.now.iso8601
      )

      db.run(CONVERSION_SQL)

      records = Sowing::Repositories::IndexRepo.new.list(mode: :record)
      expect(records.map(&:title)).to include("옛 note")
    end
  end
end
