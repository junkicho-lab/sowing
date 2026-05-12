# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::UseCases::CreateMemo do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("create-memo-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 5, 8, 9, 23, 14, "+09:00") }
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

  describe "#call" do
    context "정상 입력일 때" do
      it "Success(Memo)를 반환한다" do
        result = use_case.call(body: "오늘 1교시 수업이 활기찼다")
        expect(result).to be_success
        expect(result.value!).to be_a(Sowing::Domain::Memo)
      end

      it "메모를 마크다운 파일로 저장한다 (00_Inbox/{ts}.md)" do
        use_case.call(body: "본문")
        path = vault_dir.join("00_Inbox/2026-05-08_092314.md")
        expect(path).to exist
      end

      it "저장된 파일은 옵시디언 호환 frontmatter를 포함한다" do
        use_case.call(body: "오늘 1교시")
        path = vault_dir.join("00_Inbox/2026-05-08_092314.md")
        text = path.read
        expect(text).to start_with("---\n")
        expect(text).to include("mode: memo")
        expect(text).to include("오늘 1교시")
      end

      it "SQLite 인덱스에 row를 추가한다" do
        result = use_case.call(body: "본문")
        memo = result.value!
        indexed = index_repo.find(memo.id)
        expect(indexed).not_to be_nil
        expect(indexed.mode).to eq(:memo)
        expect(indexed.path).to eq("00_Inbox/2026-05-08_092314.md")
      end

      it "file_hash·file_mtime·word_count를 인덱스에 기록한다" do
        result = use_case.call(body: "오늘 1교시 수업이 활기찼다")
        indexed = index_repo.find(result.value!.id)
        expect(indexed.file_hash).to match(/\A[0-9a-f]{16}\z/)
        expect(indexed.file_mtime).to be > 0
        expect(indexed.word_count).to eq(4) # 공백 분리 4토큰
      end

      it "tags를 받으면 도메인과 인덱스에 모두 반영한다" do
        result = use_case.call(body: "본문", tags: ["수업", "1학년"])
        memo = result.value!
        expect(memo.tags.to_a).to eq(["1학년", "수업"])

        indexed = index_repo.find(memo.id)
        expect(indexed.tags).to eq(["1학년", "수업"])
      end

      it "ULID를 새로 생성한다" do
        memo = use_case.call(body: "본문").value!
        expect(memo.id).to be_a(Sowing::Domain::ValueObjects::Ulid)
        expect(memo.id.to_s.length).to eq(26)
      end

      it "clock.now를 created_at으로 사용한다" do
        memo = use_case.call(body: "본문").value!
        expect(memo.created_at).to eq(fixed_now)
      end

      it "본문 양 끝 공백을 strip한다" do
        memo = use_case.call(body: "  내용  ").value!
        expect(memo.body).to eq("내용")
      end
    end

    context "본문이 비어있을 때" do
      it "Failure(:empty_body)를 반환한다" do
        result = use_case.call(body: "")
        expect(result).to be_failure
        expect(result.failure).to eq(:empty_body)
      end

      it "공백만 있는 본문도 Failure(:empty_body)" do
        result = use_case.call(body: "   \n\t  ")
        expect(result).to be_failure
        expect(result.failure).to eq(:empty_body)
      end

      it "실패 시 파일·인덱스 모두 만들지 않는다" do
        use_case.call(body: "")
        expect(vault_dir.join("00_Inbox").exist?).to be false
        expect(db[:entries].count).to eq(0)
      end
    end

    context "통합 동작" do
      it "write → read round-trip이 일치한다 (VaultRepo·IndexRepo·도메인 일관성)" do
        memo = use_case.call(body: "통합 테스트", tags: ["수업"]).value!

        # VaultRepo로 다시 read
        restored = vault_repo.read("00_Inbox/2026-05-08_092314.md")
        expect(restored.id).to eq(memo.id)
        expect(restored.body).to eq("통합 테스트")
        expect(restored.tags.to_a).to eq(["수업"])

        # IndexRepo로 search_by_tag
        results = index_repo.search_by_tag("수업")
        expect(results.size).to eq(1)
        expect(results.first.id).to eq(memo.id.to_s)
      end
    end
  end
end
