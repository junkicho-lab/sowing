# frozen_string_literal: true

RSpec.describe Sowing::Repositories::IndexRepo do
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:repo) { described_class.new }
  let(:ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH") }
  let(:other_ulid) { Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZJ") }
  let(:created_at) { Time.new(2026, 5, 8, 9, 23, 14, "+09:00") }

  before do
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  def build_memo(**overrides)
    Sowing::Domain::Memo.new(
      id: ulid, body: "본문", created_at: created_at, **overrides
    )
  end

  def build_note(**overrides)
    Sowing::Domain::Note.new(
      id: ulid, body: "필기", created_at: created_at, category: "lessons", **overrides
    )
  end

  def upsert_meta(entry, **overrides)
    repo.upsert(
      entry,
      path: "00_Inbox/2026-05-08_092314.md",
      file_mtime: created_at.to_i,
      file_hash: "abcd1234ef567890", **overrides
    )
  end

  describe "#upsert" do
    context "신규 entry" do
      it "row를 삽입하고 IndexedEntry를 반환한다" do
        result = upsert_meta(build_memo(title: "1교시", tags: Sowing::Domain::ValueObjects::TagSet.new(["수업"])))
        expect(result).to be_a(Sowing::Repositories::IndexedEntry)
        expect(result.id).to eq(ulid.to_s)
        expect(result.mode).to eq(:memo)
        expect(result.title).to eq("1교시")
        expect(result.tags).to eq(["수업"])
        expect(result.path).to eq("00_Inbox/2026-05-08_092314.md")
      end

      it "indexed_at을 자동 설정한다 (현재 시각)" do
        result = upsert_meta(build_memo)
        expect(result.indexed_at).to be_a(Time)
        expect(result.indexed_at).to be_within(5).of(Time.now)
      end

      it "Note의 category·source도 인덱싱된다" do
        result = upsert_meta(build_note(title: "정리", source: "교과서"))
        expect(result.category).to eq("lessons")
        expect(result.source).to eq("교과서")
      end
    end

    context "기존 id로 다시 upsert (멱등)" do
      it "row를 덮어쓴다" do
        upsert_meta(build_memo(title: "원본"))
        result = upsert_meta(build_memo(title: "수정됨"))
        expect(result.title).to eq("수정됨")
        expect(db[:entries].where(id: ulid.to_s).count).to eq(1)
      end

      it "태그 매핑도 새로 갱신된다 (이전 태그 제거 + 새 태그)" do
        upsert_meta(build_memo(tags: Sowing::Domain::ValueObjects::TagSet.new(["수업", "1학년"])))
        result = upsert_meta(build_memo(tags: Sowing::Domain::ValueObjects::TagSet.new(["복습"])))
        expect(result.tags).to eq(["복습"])
      end
    end

    context "여러 entry가 같은 태그를 공유" do
      it "tags 테이블에 중복 row를 만들지 않는다 (정규화)" do
        upsert_meta(build_memo(id: ulid, tags: Sowing::Domain::ValueObjects::TagSet.new(["수업"])))
        upsert_meta(build_memo(id: other_ulid, tags: Sowing::Domain::ValueObjects::TagSet.new(["수업"])),
          path: "00_Inbox/other.md")
        expect(db[:tags].where(name: "수업").count).to eq(1)
        expect(db[:entry_tags].count).to eq(2)
      end
    end

    context "트랜잭션" do
      it "upsert는 db.transaction 안에서 실행된다" do
        expect(db).to receive(:transaction).and_call_original
        upsert_meta(build_memo)
      end

      it "path UNIQUE 충돌 시 트랜잭션이 롤백되어 다른 id의 새 row가 생기지 않는다" do
        upsert_meta(build_memo(id: ulid), path: "shared.md")
        expect {
          upsert_meta(build_memo(id: other_ulid), path: "shared.md")
        }.to raise_error(Sequel::UniqueConstraintViolation)
        expect(repo.find(other_ulid)).to be_nil
        expect(db[:entries].count).to eq(1)
      end
    end
  end

  describe "#find" do
    it "id로 IndexedEntry를 반환한다" do
      upsert_meta(build_memo(title: "1교시"))
      result = repo.find(ulid)
      expect(result.title).to eq("1교시")
    end

    it "Ulid 객체와 String 둘 다 받는다" do
      upsert_meta(build_memo)
      expect(repo.find(ulid)).not_to be_nil
      expect(repo.find(ulid.to_s)).not_to be_nil
    end

    it "없는 id면 nil을 반환한다" do
      expect(repo.find(other_ulid)).to be_nil
    end
  end

  describe "#list" do
    it "지정한 mode의 entry를 created_at 내림차순으로 반환한다" do
      old = Time.new(2026, 5, 1, 0, 0, 0, "+09:00")
      new = Time.new(2026, 5, 8, 0, 0, 0, "+09:00")
      upsert_meta(build_memo(id: ulid, created_at: old), path: "00_Inbox/old.md")
      upsert_meta(build_memo(id: other_ulid, created_at: new), path: "00_Inbox/new.md")

      results = repo.list(mode: :memo)
      expect(results.size).to eq(2)
      expect(results.first.created_at).to eq(new)
      expect(results.last.created_at).to eq(old)
    end

    it "다른 mode는 포함하지 않는다" do
      upsert_meta(build_memo(id: ulid))
      upsert_meta(build_note(id: other_ulid, title: "n"), path: "20_Notes/lessons/n.md")

      expect(repo.list(mode: :memo).size).to eq(1)
      expect(repo.list(mode: :note).size).to eq(1)
    end

    it "지원하지 않는 mode면 ArgumentError" do
      expect { repo.list(mode: :alien) }.to raise_error(ArgumentError, /mode/)
    end

    context "limit·offset" do
      before do
        5.times do |i|
          upsert_meta(
            build_memo(id: Sowing::Domain::ValueObjects::Ulid.generate,
              created_at: Time.new(2026, 5, i + 1, 0, 0, 0, "+09:00")),
            path: "00_Inbox/#{i}.md"
          )
        end
      end

      it "limit으로 행 수를 제한한다" do
        expect(repo.list(mode: :memo, limit: 2).size).to eq(2)
      end

      it "offset으로 행을 건너뛴다" do
        all = repo.list(mode: :memo)
        rest = repo.list(mode: :memo, offset: 2)
        expect(rest).to eq(all.drop(2))
      end

      it "limit + offset 조합으로 페이징이 가능하다" do
        page1 = repo.list(mode: :memo, limit: 2, offset: 0)
        page2 = repo.list(mode: :memo, limit: 2, offset: 2)
        page3 = repo.list(mode: :memo, limit: 2, offset: 4)
        expect(page1.size).to eq(2)
        expect(page2.size).to eq(2)
        expect(page3.size).to eq(1)
        expect((page1 + page2 + page3).map(&:id).uniq.size).to eq(5)
      end
    end
  end

  describe "#count" do
    it "해당 모드의 row 수를 반환한다" do
      upsert_meta(build_memo(id: ulid))
      upsert_meta(build_memo(id: other_ulid), path: "00_Inbox/b.md")
      expect(repo.count(mode: :memo)).to eq(2)
      expect(repo.count(mode: :note)).to eq(0)
    end

    it "지원하지 않는 mode면 ArgumentError" do
      expect { repo.count(mode: :alien) }.to raise_error(ArgumentError, /mode/)
    end
  end

  describe "#delete" do
    it "row를 제거하고 true를 반환한다" do
      upsert_meta(build_memo)
      expect(repo.delete(ulid)).to be true
      expect(repo.find(ulid)).to be_nil
    end

    it "없는 id면 false" do
      expect(repo.delete(other_ulid)).to be false
    end

    it "entry_tags도 CASCADE로 함께 삭제된다 (FK)" do
      upsert_meta(build_memo(tags: Sowing::Domain::ValueObjects::TagSet.new(["수업"])))
      repo.delete(ulid)
      expect(db[:entry_tags].count).to eq(0)
    end
  end

  describe "#search_by_tag" do
    before do
      upsert_meta(
        build_memo(id: ulid, tags: Sowing::Domain::ValueObjects::TagSet.new(["수업", "1학년"])),
        path: "00_Inbox/a.md"
      )
      upsert_meta(
        build_memo(id: other_ulid, tags: Sowing::Domain::ValueObjects::TagSet.new(["복습"])),
        path: "00_Inbox/b.md"
      )
    end

    it "해당 태그를 가진 entry만 반환한다" do
      results = repo.search_by_tag("수업")
      expect(results.size).to eq(1)
      expect(results.first.id).to eq(ulid.to_s)
    end

    it "case-insensitive 매칭이다 (COLLATE NOCASE)" do
      upsert_meta(
        build_memo(id: Sowing::Domain::ValueObjects::Ulid.generate,
          tags: Sowing::Domain::ValueObjects::TagSet.new(["english"])),
        path: "00_Inbox/c.md"
      )
      expect(repo.search_by_tag("ENGLISH").size).to eq(1)
      expect(repo.search_by_tag("English").size).to eq(1)
    end

    it "공백·대소문자 차이가 있는 입력도 정규화 후 매칭한다" do
      expect(repo.search_by_tag("  수업  ").size).to eq(1)
    end

    it "없는 태그면 빈 배열" do
      expect(repo.search_by_tag("없는태그")).to eq([])
    end
  end

  describe "#search_by_date" do
    before do
      [
        Time.new(2026, 5, 1, 0, 0, 0, "+09:00"),
        Time.new(2026, 5, 5, 12, 0, 0, "+09:00"),
        Time.new(2026, 5, 10, 0, 0, 0, "+09:00")
      ].each_with_index do |t, i|
        upsert_meta(
          build_memo(id: Sowing::Domain::ValueObjects::Ulid.generate, created_at: t),
          path: "00_Inbox/#{i}.md"
        )
      end
    end

    it "범위 내 entry만 created_at 내림차순으로 반환한다" do
      from = Time.new(2026, 5, 4, 0, 0, 0, "+09:00")
      to = Time.new(2026, 5, 8, 0, 0, 0, "+09:00")
      results = repo.search_by_date(from: from, to: to)
      expect(results.size).to eq(1)
      expect(results.first.created_at).to eq(Time.new(2026, 5, 5, 12, 0, 0, "+09:00"))
    end

    it "양 끝이 inclusive다" do
      exact = Time.new(2026, 5, 1, 0, 0, 0, "+09:00")
      results = repo.search_by_date(from: exact, to: exact)
      expect(results.size).to eq(1)
    end

    it "from·to가 Time이 아니면 ArgumentError" do
      expect { repo.search_by_date(from: "2026-05-01", to: Time.now) }
        .to raise_error(ArgumentError, /Time/)
    end
  end
end
