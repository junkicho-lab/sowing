# frozen_string_literal: true

# 위키링크 그래프 인덱스 (W3-T02). links 테이블 + IndexRepo 자동 동기화.

RSpec.describe Sowing::Repositories::IndexRepo, "위키링크 그래프" do
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:repo) { described_class.new }
  let(:created_at) { Time.new(2026, 5, 8, 9, 0, 0, "+09:00") }

  before do
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  def make_note(title:, body: "", category: "lessons", source: "교과서", id: Sowing::Domain::ValueObjects::Ulid.generate)
    Sowing::Domain::Note.new(
      id: id,
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

  describe "links 테이블이 마이그레이션 003으로 생성된다" do
    it "테이블 + 컬럼이 존재한다" do
      expect(db.tables).to include(:links)
      cols = db.schema(:links).map(&:first)
      expect(cols).to include(:source_id, :target_id, :target_text)
    end
  end

  describe "sync_outbound_links — entry.body에서 추출 + insert" do
    it "본문에 위키링크가 없으면 links row 0개" do
      a = make_note(title: "A", body: "위키링크 없음")
      upsert(a)
      expect(repo.links_from(a.id)).to be_empty
    end

    it "[[target]]을 추출하여 row를 만든다 (broken — 매칭 entry 없음)" do
      a = make_note(title: "A", body: "참조: [[Other]]")
      upsert(a)

      links = repo.links_from(a.id)
      expect(links.size).to eq(1)
      expect(links.first[:target_text]).to eq("Other")
      expect(links.first[:target_id]).to be_nil # broken
    end

    it "여러 위키링크 + 중복 target은 하나로 dedupe (target_text 기준)" do
      a = make_note(title: "A", body: "[[X]] [[Y]] [[X|별칭]]")
      upsert(a)

      links = repo.links_from(a.id)
      expect(links.map { |l| l[:target_text] }.sort).to eq(%w[X Y])
    end

    it "재upsert 시 옛 링크는 모두 삭제되고 새로 insert (멱등)" do
      same_id = Sowing::Domain::ValueObjects::Ulid.generate
      a1 = make_note(id: same_id, title: "A", body: "[[X]] [[Y]]")
      upsert(a1)
      expect(repo.links_from(same_id).size).to eq(2)

      a2 = make_note(id: same_id, title: "A", body: "[[Z]]")
      upsert(a2)
      links = repo.links_from(same_id)
      expect(links.size).to eq(1)
      expect(links.first[:target_text]).to eq("Z")
    end
  end

  describe "title 정확 일치로 target_id 매칭" do
    it "이미 존재하는 entry의 title과 일치하면 target_id가 채워진다" do
      target = make_note(title: "Other", body: "본문")
      upsert(target)

      source = make_note(title: "Source", body: "[[Other]]")
      upsert(source)

      link = repo.links_from(source.id).first
      expect(link[:target_id]).to eq(target.id.to_s)
    end

    it "case-sensitive (다른 대소문자는 broken)" do
      target = make_note(title: "Other", body: "")
      upsert(target)

      source = make_note(title: "Source", body: "[[OTHER]]")
      upsert(source)

      expect(repo.links_from(source.id).first[:target_id]).to be_nil
    end
  end

  describe "relink_broken_to — 새 entry 추가 시 broken 자동 fix" do
    it "broken link의 target_text와 새 entry title이 일치하면 target_id를 채운다" do
      source = make_note(title: "Source", body: "[[FutureNote]]")
      upsert(source)
      expect(repo.broken_links.size).to eq(1)

      target = make_note(title: "FutureNote", body: "")
      upsert(target)

      expect(repo.broken_links).to be_empty
      expect(repo.links_from(source.id).first[:target_id]).to eq(target.id.to_s)
    end

    it "title이 nil인 entry(메모)는 broken을 fix하지 않는다" do
      source = make_note(title: "Source", body: "[[Memo]]")
      upsert(source)

      memo = Sowing::Domain::Memo.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        body: "메모 본문",
        created_at: created_at
      )
      repo.upsert(memo, path: "00_Inbox/m.md", file_mtime: 0, file_hash: "0" * 16)

      expect(repo.links_from(source.id).first[:target_id]).to be_nil
    end
  end

  describe "nullify_stale_inbound_links — title 변경 시 옛 inbound 링크 broken 처리" do
    it "title이 변경되면 옛 title로 들어오던 링크가 broken으로 강등된다" do
      target_id = Sowing::Domain::ValueObjects::Ulid.generate
      target1 = make_note(id: target_id, title: "Original", body: "")
      upsert(target1)

      source = make_note(title: "Source", body: "[[Original]]")
      upsert(source)
      expect(repo.links_from(source.id).first[:target_id]).to eq(target_id.to_s)

      # title 변경 (path도 바뀌므로 path_override로 지정)
      target2 = make_note(id: target_id, title: "Renamed", body: "")
      upsert(target2, path_override: "20_Notes/lessons/Renamed.md")

      expect(repo.links_from(source.id).first[:target_id]).to be_nil
    end

    it "title 변경 + 다른 broken이 새 title과 일치하면 자동 fix" do
      target_id = Sowing::Domain::ValueObjects::Ulid.generate
      a1 = make_note(id: target_id, title: "A", body: "")
      upsert(a1)

      pending_link = make_note(title: "Source", body: "[[Renamed]]")
      upsert(pending_link)
      expect(repo.broken_links.size).to eq(1)

      a2 = make_note(id: target_id, title: "Renamed", body: "")
      upsert(a2, path_override: "20_Notes/lessons/Renamed.md")

      expect(repo.broken_links).to be_empty
      expect(repo.links_from(pending_link.id).first[:target_id]).to eq(target_id.to_s)
    end
  end

  describe "links_to — backlinks" do
    it "특정 entry로 들어오는 링크 목록을 반환한다" do
      target = make_note(title: "Hub", body: "")
      upsert(target)
      a = make_note(title: "A", body: "[[Hub]]")
      upsert(a)
      b = make_note(title: "B", body: "[[Hub]]")
      upsert(b)

      backlinks = repo.links_to(target.id)
      expect(backlinks.size).to eq(2)
      expect(backlinks.map { |l| l[:source_id] }).to contain_exactly(a.id.to_s, b.id.to_s)
    end
  end

  describe "broken_links — 모든 깨진 링크 조회" do
    it "여러 source의 broken을 모아서 반환한다" do
      a = make_note(title: "A", body: "[[Missing1]] [[Missing2]]")
      upsert(a)
      b = make_note(title: "B", body: "[[Missing1]]")
      upsert(b)

      broken = repo.broken_links
      expect(broken.size).to eq(3)
      expect(broken.map { |l| l[:target_text] }).to contain_exactly("Missing1", "Missing1", "Missing2")
    end
  end

  describe "FK CASCADE / SET NULL" do
    it "source_id의 entry가 삭제되면 그 source의 link들이 CASCADE 삭제된다" do
      target = make_note(title: "Target", body: "")
      upsert(target)
      source = make_note(title: "Source", body: "[[Target]]")
      upsert(source)
      expect(db[:links].where(source_id: source.id.to_s).count).to eq(1)

      repo.delete(source.id)
      expect(db[:links].where(source_id: source.id.to_s).count).to eq(0)
    end

    it "target_id의 entry가 삭제되면 inbound 링크는 SET NULL (broken 변환)" do
      target = make_note(title: "Target", body: "")
      upsert(target)
      source = make_note(title: "Source", body: "[[Target]]")
      upsert(source)
      expect(repo.links_from(source.id).first[:target_id]).to eq(target.id.to_s)

      repo.delete(target.id)

      link = repo.links_from(source.id).first
      expect(link).not_to be_nil
      expect(link[:target_id]).to be_nil # broken
      expect(link[:target_text]).to eq("Target")
    end
  end

  describe "트랜잭션 — entries upsert와 links 동기화는 원자적" do
    it "entries 업서트가 path UNIQUE에서 실패하면 links도 롤백" do
      a = make_note(title: "A", body: "[[X]]")
      upsert(a)
      expect(repo.links_from(a.id).size).to eq(1)

      b = make_note(title: "B", body: "[[Y]]")
      expect {
        upsert(b, path_override: "20_Notes/lessons/A.md")
      }.to raise_error(Sequel::UniqueConstraintViolation)

      expect(repo.links_from(b.id)).to be_empty
    end
  end
end
