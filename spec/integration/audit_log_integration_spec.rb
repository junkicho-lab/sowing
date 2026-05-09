# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

# Persistence#persist! / #repersist! / #unpersist! 가 audit log 에 자동 기록하는지 검증.
# AuditLog 자체 단위 테스트는 spec/infrastructure/audit_log_spec.rb.
RSpec.describe "Persistence audit log 통합 (W9-T01)" do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("audit-integration-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Infrastructure::DB.connection }

  # Persistence 가 호출하는 AuditLog.instance 를 spec vault 로 격리.
  let!(:audit_log) { Sowing::Infrastructure::AuditLog.new(vault_dir: vault_dir) }

  before do
    Sowing::Infrastructure::AuditLog.instance = audit_log
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after do
    Sowing::Infrastructure::AuditLog.instance = nil # 다음 spec 은 default 로 복귀
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  describe "EVALUATION 검증 시나리오 — 메모/필기/기록 5건 mutation → 5줄" do
    it "create memo + create note + update note + create record + delete sample" do
      # 1. 메모 작성
      memo = Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "오늘 메모").value!

      # 2. 필기 작성
      note_result = Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "원본", body: "본문", category: "lessons", source: "교과서")
      note = note_result.value!

      # 3. 필기 수정
      Sowing::UseCases::UpdateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(id: note.id, title: "수정", body: "수정 본문",
          category: "lessons", source: "교과서")

      # 4. 기록 작성
      Sowing::UseCases::CreateRecord.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "회고", body: "본문", category: "회고")

      # 5. 메모 삭제 (unpersist!)
      delete_uc = Sowing::UseCases::DeleteSamples.new(vault_repo: vault_repo, index_repo: index_repo)
      indexed_memo = index_repo.find(memo.id)
      # find_samples 는 prefix 매칭이라 일반 entry 는 안 잡힘 — 직접 unpersist! 호출.
      delete_uc.send(:unpersist!, indexed_memo)

      records = audit_log.read_all
      expect(records.size).to eq(5)
      actions = records.map { |r| r["action"] }
      expect(actions).to eq(%w[create create update create delete])

      # 모든 줄이 JSON 파싱 가능 (read_all 이 이미 파싱했으니 통과)
      records.each do |r|
        expect(r["ts"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
        expect(r["entry_id"]).to match(/\A01[A-Z0-9]+/) # ULID prefix
        expect(%w[memo note record]).to include(r["mode"])
        expect(r["path"]).not_to start_with("/") # vault-기준 상대경로
      end
    end
  end

  describe "각 액션별 단위 검증" do
    it ":create 는 old_hash=nil, new_hash 있음, mode 일치" do
      Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "X")
      record = audit_log.read_all.first
      expect(record["action"]).to eq("create")
      expect(record["mode"]).to eq("memo")
      expect(record["old_hash"]).to be_nil
      expect(record["new_hash"]).to match(/\A[a-f0-9]{16}\z/)
    end

    it ":update 는 old_hash 와 new_hash 모두 있음, 둘이 다름" do
      note = Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "T", body: "v1", category: "lessons", source: "교과서").value!
      audit_log.clear! # create 줄 제거

      Sowing::UseCases::UpdateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(id: note.id, title: "T", body: "v2", category: "lessons", source: "교과서")

      record = audit_log.read_all.first
      expect(record["action"]).to eq("update")
      expect(record["old_hash"]).to match(/\A[a-f0-9]{16}\z/)
      expect(record["new_hash"]).to match(/\A[a-f0-9]{16}\z/)
      expect(record["old_hash"]).not_to eq(record["new_hash"])
    end

    it ":delete 는 old_hash 있음, new_hash=nil" do
      memo = Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "삭제 대상").value!
      audit_log.clear!

      indexed = index_repo.find(memo.id)
      Sowing::UseCases::DeleteSamples.new(vault_repo: vault_repo, index_repo: index_repo)
        .send(:unpersist!, indexed)

      record = audit_log.read_all.first
      expect(record["action"]).to eq("delete")
      expect(record["old_hash"]).to match(/\A[a-f0-9]{16}\z/)
      expect(record["new_hash"]).to be_nil
    end

    it "PromoteToNote 는 :update 로 기록됨 (mode 변화는 record 의 mode 필드로 표현)" do
      memo = Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "승격 대상").value!
      audit_log.clear!

      Sowing::UseCases::PromoteToNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(id: memo.id, title: "승격됨", category: "lessons", source: "교과서")

      record = audit_log.read_all.first
      expect(record["action"]).to eq("update")
      expect(record["mode"]).to eq("note") # 승격 후 모드
      expect(record["entry_id"]).to eq(memo.id.to_s) # ID 보존
    end
  end

  describe ":adopt 와 :reindex 는 actor=filesystem (W5 watcher 경로)" do
    it "AdoptOrphan → :adopt + actor=filesystem" do
      orphan_dir = vault_dir.join("00_Inbox")
      FileUtils.mkdir_p(orphan_dir)
      orphan = orphan_dir.join("외부.md")
      File.write(orphan, "외부에서 만든 메모")

      Sowing::UseCases::AdoptOrphan.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(type: :added, path: orphan)

      record = audit_log.read_all.first
      expect(record["action"]).to eq("adopt")
      expect(record["actor"]).to eq("filesystem")
      expect(record["mode"]).to eq("memo")
    end

    it "ReindexEntry :modified → :reindex + actor=filesystem" do
      note = Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(title: "T", body: "v1", category: "lessons", source: "교과서").value!
      abs = vault_dir.join(index_repo.find(note.id).path)
      File.write(abs, abs.read.sub("v1", "외부에서 수정"))
      sleep 1.1 # POSIX mtime 1초 단위
      audit_log.clear!

      Sowing::UseCases::ReindexEntry.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(type: :modified, path: abs)

      record = audit_log.read_all.first
      expect(record["action"]).to eq("reindex")
      expect(record["actor"]).to eq("filesystem")
      expect(record["old_hash"]).not_to eq(record["new_hash"])
    end
  end

  describe "회귀 — 기존 use case 동작 변화 없음" do
    it "CreateMemo: audit 추가되어도 entry 정상 작성 + 인덱스 등록" do
      result = Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "정상 동작 확인")
      expect(result).to be_success
      expect(index_repo.count(mode: :memo)).to eq(1)
    end

    it "PromoteToNote: ID 유지 + 옛 path 휴지통 (W3-T06 기존 동작)" do
      memo = Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: "메모").value!
      old_path = index_repo.find(memo.id).path

      Sowing::UseCases::PromoteToNote.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(id: memo.id, title: "필기", category: "lessons", source: "교과서")

      indexed = index_repo.find(memo.id)
      expect(indexed.id.to_s).to eq(memo.id.to_s)
      expect(indexed.mode).to eq(:note)
      # 옛 메모 파일은 휴지통으로
      expect(vault_dir.join(".sowing/trash", old_path)).to exist
    end
  end
end
