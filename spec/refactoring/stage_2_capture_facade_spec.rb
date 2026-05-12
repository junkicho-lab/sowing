# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Phase R Stage 2 R2-T03 — Sowing::Capture Façade 실 구현.
# Façade 가 Item + ItemRepo 를 올바르게 조립하여 외부에 안정 API 노출하는지 검증.
RSpec.describe "Sowing::Capture Façade (Stage 2 R2-T03)" do
  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("capture-facade-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }

  before do
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete
    # 임시 vault 를 사용하는 ItemRepo 강제 주입
    Sowing::Capture.repo = Sowing::Capture::ItemRepo.new(
      vault_repo: vault_repo, index_repo: index_repo
    )
  end

  after do
    Sowing::Capture.reset_repo!
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  describe ".create_item" do
    it "최소 인자 (body) 로 Item 생성·저장" do
      item = Sowing::Capture.create_item(body: "오늘 1교시 활기찼다")
      expect(item).to be_a(Sowing::Capture::Item)
      expect(item.body).to eq("오늘 1교시 활기찼다")
      expect(item.subject).to be_nil
      expect(item.id).to be_a(Sowing::Domain::ValueObjects::Ulid)
    end

    it "subject 4축 모두 허용" do
      Sowing::Capture::Item::SUBJECTS.each do |axis|
        item = Sowing::Capture.create_item(body: "본문 #{axis}", subject: axis)
        expect(item.subject).to eq(axis)
      end
    end

    it "옵션 인자 (title·tags·template) 전달" do
      item = Sowing::Capture.create_item(
        body: "본문", title: "수업 메모",
        tags: ["수업", "1학년"], template: "lesson_reflection"
      )
      expect(item.title).to eq("수업 메모")
      expect(item.tags.to_a).to contain_exactly("수업", "1학년")
      expect(item.template).to eq("lesson_reflection")
    end

    it "tags 가 TagSet 이어도 받아들임" do
      tagset = Sowing::Domain::ValueObjects::TagSet.new(["수업"])
      item = Sowing::Capture.create_item(body: "본문", tags: tagset)
      expect(item.tags).to eq(tagset)
    end

    it "body 가 빈 문자열이면 ArgumentError" do
      expect { Sowing::Capture.create_item(body: "") }.to raise_error(ArgumentError, /body/)
    end

    it "body 가 공백뿐이어도 ArgumentError" do
      expect { Sowing::Capture.create_item(body: "  \n  ") }.to raise_error(ArgumentError, /body/)
    end

    it "subject 가 4축 밖이면 ArgumentError (Item validation)" do
      expect { Sowing::Capture.create_item(body: "본문", subject: :random) }
        .to raise_error(ArgumentError, /subject/)
    end
  end

  describe ".find" do
    it "create 후 같은 id 로 round-trip" do
      created = Sowing::Capture.create_item(body: "본문", subject: :person)
      found = Sowing::Capture.find(created.id)
      expect(found.id).to eq(created.id)
      expect(found.subject).to eq(:person)
    end

    it "존재하지 않으면 nil" do
      bogus_id = Sowing::Domain::ValueObjects::Ulid.parse("01KR1FE1QYH4EEP6RAGR9DJ6ZH")
      expect(Sowing::Capture.find(bogus_id)).to be_nil
    end
  end

  describe ".recent" do
    it "여러 Item 을 최신순으로 반환" do
      Sowing::Capture.create_item(body: "첫째", created_at: Time.new(2026, 5, 12, 9, 0, 0))
      Sowing::Capture.create_item(body: "둘째", created_at: Time.new(2026, 5, 12, 10, 0, 0))
      Sowing::Capture.create_item(body: "셋째", created_at: Time.new(2026, 5, 12, 11, 0, 0))

      result = Sowing::Capture.recent(limit: 10)
      expect(result.map(&:body)).to eq(["셋째", "둘째", "첫째"])
    end

    it "limit 적용" do
      3.times { |i| Sowing::Capture.create_item(body: "본문 #{i}") }
      expect(Sowing::Capture.recent(limit: 2).size).to eq(2)
    end
  end
end
