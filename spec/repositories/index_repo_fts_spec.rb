# frozen_string_literal: true

# FTS5 전문 검색 (W4-T01).
# trigram 토크나이저 — 3글자 이상 query만 매칭. 2글자 이하는 W4-T02 LIKE 폴백 영역.

RSpec.describe Sowing::Repositories::IndexRepo, "전문 검색 (FTS5)" do
  let(:db) { Sowing::Core::DB.connection }
  let(:repo) { described_class.new }
  let(:created_at) { Time.new(2026, 5, 8, 9, 0, 0, "+09:00") }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  def make_note(title:, body:, category: "lessons", source: "교과서")
    Sowing::Domain::Note.new(
      id: Sowing::Domain::ValueObjects::Ulid.generate,
      title: title,
      body: body,
      category: category,
      source: source,
      created_at: created_at
    )
  end

  def upsert(entry, path_override: nil)
    repo.upsert(
      entry,
      path: path_override || "20_Notes/lessons/#{entry.title}.md",
      file_mtime: created_at.to_i,
      file_hash: "deadbeef12345678"
    )
  end

  describe "마이그레이션 004" do
    it "entries_fts 가상 테이블이 생성된다" do
      expect(db.tables).to include(:entries_fts)
    end

    it "trigram 토크나이저로 설정됨 (sqlite_master 참조)" do
      sql = db.fetch("SELECT sql FROM sqlite_master WHERE name = 'entries_fts'").first[:sql]
      expect(sql).to include("trigram")
    end
  end

  describe "upsert 시 entries_fts 자동 동기화" do
    it "신규 entry → entries_fts에 row 추가" do
      a = make_note(title: "협동학습 정리", body: "본문 내용")
      upsert(a)
      row = db[:entries_fts].where(id: a.id.to_s).first
      expect(row).not_to be_nil
      expect(row[:title]).to eq("협동학습 정리")
      expect(row[:body]).to eq("본문 내용")
    end

    it "재upsert 시 옛 row 제거 + 새 row (멱등, 같은 ID로 title 변경)" do
      a = make_note(title: "원본", body: "원본 본문")
      upsert(a)

      a2 = Sowing::Domain::Note.new(
        id: a.id, # 같은 ID
        title: "원본 v2",
        body: "본문 수정됨",
        category: "lessons",
        source: "교과서",
        created_at: created_at
      )
      upsert(a2, path_override: "20_Notes/lessons/원본 v2.md")

      rows = db[:entries_fts].where(id: a.id.to_s).all
      expect(rows.size).to eq(1)
      expect(rows.first[:title]).to eq("원본 v2")
      expect(rows.first[:body]).to eq("본문 수정됨")
    end

    it "트랜잭션 롤백 시 entries_fts도 함께 롤백 (path UNIQUE 충돌)" do
      a = make_note(title: "A", body: "본문")
      upsert(a)
      expect(db[:entries_fts].count).to eq(1)

      b = make_note(title: "B", body: "다른 본문")
      expect {
        # 같은 path로 다른 id → entries.path UNIQUE 충돌
        upsert(b, path_override: "20_Notes/lessons/A.md")
      }.to raise_error(Sequel::UniqueConstraintViolation)

      # b의 fts row도 만들어지지 않음
      expect(db[:entries_fts].where(id: b.id.to_s).count).to eq(0)
    end
  end

  describe "delete 시 entries_fts 동기화" do
    it "entry 삭제하면 entries_fts에서도 제거" do
      a = make_note(title: "삭제할 항목", body: "본문")
      upsert(a)
      expect(db[:entries_fts].where(id: a.id.to_s).count).to eq(1)

      repo.delete(a.id)
      expect(db[:entries_fts].where(id: a.id.to_s).count).to eq(0)
    end
  end

  describe "#search_full_text — trigram 매칭" do
    before do
      upsert(make_note(title: "협동학습 정리", body: "협동학습은 학생이 함께 배우는 방법"))
      upsert(make_note(title: "수업철학 기록", body: "오늘 1교시 수업이 활기찼다 정말로"))
      upsert(make_note(title: "독서 노트", body: "책에서 영감을 얻었다"))
    end

    it "3글자 이상 한국어 query는 매칭됨" do
      results = repo.search_full_text(q: "협동학습")
      expect(results.size).to eq(1)
      expect(results.first.title).to eq("협동학습 정리")
    end

    it "본문에서 매칭 (title 외)" do
      results = repo.search_full_text(q: "활기찼다")
      expect(results.size).to eq(1)
      expect(results.first.title).to eq("수업철학 기록")
    end

    it "여러 entry에서 매칭되는 단어" do
      upsert(make_note(title: "협동학습 더하기", body: "추가"))
      results = repo.search_full_text(q: "협동학습")
      expect(results.size).to eq(2)
    end

    it "title과 body 모두 검색 대상" do
      upsert(make_note(title: "별개 제목", body: "여기에도 협동학습 단어"))
      results = repo.search_full_text(q: "협동학습")
      expect(results.size).to eq(2)
    end

    it "매칭 안 되면 빈 배열" do
      expect(repo.search_full_text(q: "없는키워드123")).to be_empty
    end

    it "빈 query → 빈 배열" do
      expect(repo.search_full_text(q: "")).to eq([])
      expect(repo.search_full_text(q: "  ")).to eq([])
    end

    it "limit 적용" do
      5.times { |i| upsert(make_note(title: "협동학습 #{i}", body: "본문")) }
      expect(repo.search_full_text(q: "협동학습", limit: 3).size).to eq(3)
    end

    it "결과는 IndexedEntry 인스턴스" do
      results = repo.search_full_text(q: "협동학습")
      expect(results.first).to be_a(Sowing::Repositories::IndexedEntry)
    end
  end

  describe "trigram의 한계 (W4-T01 명시)" do
    before do
      upsert(make_note(title: "수업", body: "본문"))
    end

    it "2글자 한국어 query는 매칭되지 않는다 — W4-T02 LIKE 폴백 영역" do
      expect(repo.search_full_text(q: "수업")).to be_empty
    end

    it "1글자 query도 매칭되지 않는다" do
      expect(repo.search_full_text(q: "수")).to be_empty
    end
  end

  describe "재인덱싱 가능성 (CLAUDE.md 원칙 1: SQLite는 캐시)" do
    it "entries_fts를 비워도 upsert 다시 호출 시 재구축됨" do
      a = make_note(title: "복원 테스트", body: "본문 데이터")
      upsert(a)
      db[:entries_fts].delete
      expect(db[:entries_fts].count).to eq(0)

      # 같은 entry 재upsert → fts에 다시 채워짐
      upsert(a)
      expect(db[:entries_fts].where(id: a.id.to_s).count).to eq(1)
    end
  end
end
