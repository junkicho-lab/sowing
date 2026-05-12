# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::CreateNote do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("create-note-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 5, 8, 14, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  let(:use_case) {
    described_class.new(vault_repo: vault_repo, index_repo: index_repo, clock: clock)
  }

  before do
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after do
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  def valid_attrs(**overrides)
    {
      title: "협동학습 정리",
      body: "협동학습은 ...",
      category: "trainings",
      source: "2026 봄 협동학습 연수",
      tags: ["연수"]
    }.merge(overrides)
  end

  describe "#call" do
    context "정상 입력일 때" do
      it "Success(Note)를 반환한다" do
        result = use_case.call(**valid_attrs)
        expect(result).to be_success
        expect(result.value!).to be_a(Sowing::Domain::Note)
      end

      it "20_Notes/{category}/{title}.md 경로에 마크다운을 저장한다" do
        use_case.call(**valid_attrs)
        path = vault_dir.join("20_Notes/trainings/협동학습 정리.md")
        expect(path).to exist
      end

      it "SQLite 인덱스에 row를 추가하고 category·source가 기록된다" do
        result = use_case.call(**valid_attrs)
        indexed = index_repo.find(result.value!.id)
        expect(indexed.mode).to eq(:note)
        expect(indexed.category).to eq("trainings")
        expect(indexed.source).to eq("2026 봄 협동학습 연수")
      end

      it "tags가 정규화되어 저장된다" do
        result = use_case.call(**valid_attrs(tags: ["수업", "1학년", "수업"]))
        expect(result.value!.tags.to_a).to eq(["1학년", "수업"])
      end
    end

    context "필수 필드 누락" do
      it "title이 비어 있으면 :empty_title" do
        result = use_case.call(**valid_attrs(title: "  "))
        expect(result).to be_failure
        expect(result.failure).to eq(:empty_title)
      end

      it "body가 비어 있으면 :empty_body" do
        result = use_case.call(**valid_attrs(body: ""))
        expect(result.failure).to eq(:empty_body)
      end

      it "category가 비어 있으면 :empty_category" do
        result = use_case.call(**valid_attrs(category: ""))
        expect(result.failure).to eq(:empty_category)
      end

      it "source가 비어 있으면 :empty_source" do
        result = use_case.call(**valid_attrs(source: " \t  "))
        expect(result.failure).to eq(:empty_source)
      end

      it "실패 시 파일·인덱스 모두 만들지 않는다" do
        use_case.call(**valid_attrs(title: ""))
        expect(vault_dir.join("20_Notes").exist?).to be false
        expect(db[:entries].count).to eq(0)
      end
    end

    context "category enum 검증" do
      it "허용 외 카테고리는 :invalid_category" do
        result = use_case.call(**valid_attrs(category: "alien"))
        expect(result.failure).to eq(:invalid_category)
      end

      it "lessons / trainings / books / meetings 모두 허용한다" do
        %w[lessons trainings books meetings].each do |cat|
          db[:entry_tags].delete
          db[:entries].delete
          FileUtils.rm_rf(vault_dir)
          FileUtils.mkdir_p(vault_dir)
          result = use_case.call(**valid_attrs(category: cat, title: "T-#{cat}"))
          expect(result).to be_success, "category=#{cat}: #{result.failure if result.failure?}"
        end
      end
    end
  end
end
