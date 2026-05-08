# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::CreateRecord do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("create-record-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:fixed_now) { Time.new(2026, 5, 8, 20, 30, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  let(:use_case) {
    described_class.new(vault_repo: vault_repo, index_repo: index_repo, clock: clock)
  }

  before do
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  def valid_attrs(**overrides)
    {
      title: "5월 학급운영 회고",
      body: "이번 달 돌아보기.",
      category: "학급운영",
      tags: ["회고"]
    }.merge(overrides)
  end

  describe "#call" do
    context "정상 입력" do
      it "Success(Record)를 반환한다" do
        result = use_case.call(**valid_attrs)
        expect(result).to be_success
        expect(result.value!).to be_a(Sowing::Domain::Record)
      end

      it "30_Records/{YYYY}/{category}/{title}.md 경로에 저장한다" do
        use_case.call(**valid_attrs)
        path = vault_dir.join("30_Records/2026/학급운영/5월 학급운영 회고.md")
        expect(path).to exist
      end

      it "category는 자유 텍스트라 임의 한국어 허용 (Note의 enum과 다름)" do
        result = use_case.call(**valid_attrs(category: "수업철학"))
        expect(result).to be_success
        expect(vault_dir.join("30_Records/2026/수업철학/5월 학급운영 회고.md")).to exist
      end

      it "promoted_from을 인덱스에 기록한다" do
        result = use_case.call(**valid_attrs(promoted_from: "00_Inbox/2026-05-01_120000.md"))
        indexed = index_repo.find(result.value!.id)
        expect(indexed.promoted_from).to eq("00_Inbox/2026-05-01_120000.md")
      end

      it "category 양 끝 공백을 strip한다 (디렉토리 안전성)" do
        use_case.call(**valid_attrs(category: "  학급운영  "))
        expect(vault_dir.join("30_Records/2026/학급운영/5월 학급운영 회고.md")).to exist
      end
    end

    context "검증 실패" do
      it "title 비면 :empty_title" do
        expect(use_case.call(**valid_attrs(title: "")).failure).to eq(:empty_title)
      end

      it "body 비면 :empty_body" do
        expect(use_case.call(**valid_attrs(body: "  ")).failure).to eq(:empty_body)
      end

      it "category 비면 :empty_category" do
        expect(use_case.call(**valid_attrs(category: "")).failure).to eq(:empty_category)
      end

      it "Note와 달리 category enum 검증은 없다 (자유 텍스트)" do
        result = use_case.call(**valid_attrs(category: "임의의카테고리"))
        expect(result).to be_success
      end
    end
  end
end
