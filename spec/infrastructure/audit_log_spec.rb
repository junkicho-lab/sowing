# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Sowing::Core::AuditLog do
  let(:tmpdir) { Pathname.new(Dir.mktmpdir("audit-log-spec-")) }
  let(:fixed_now) { Time.new(2026, 5, 9, 14, 23, 14, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }
  subject(:log) { described_class.new(vault_dir: tmpdir, clock: clock) }

  after { FileUtils.rm_rf(tmpdir) if tmpdir.exist? }

  describe "#append" do
    it "기본 케이스 — 한 줄 JSON Lines 로 추가됨" do
      log.append(action: :create, entry_id: "01ABC", mode: "memo", path: "00_Inbox/x.md", new_hash: "abc")
      expect(log.path).to exist
      lines = log.path.each_line.to_a
      expect(lines.size).to eq(1)
      record = JSON.parse(lines.first)
      expect(record["action"]).to eq("create")
      expect(record["entry_id"]).to eq("01ABC")
      expect(record["mode"]).to eq("memo")
      expect(record["path"]).to eq("00_Inbox/x.md")
      expect(record["new_hash"]).to eq("abc")
      expect(record["old_hash"]).to be_nil
      expect(record["actor"]).to eq("user")
      expect(record["ts"]).to eq(fixed_now.iso8601)
    end

    it "여러 번 호출 → 줄 단위 누적 (append-only)" do
      log.append(action: :create, entry_id: "01A", mode: "memo", path: "a.md")
      log.append(action: :update, entry_id: "01A", mode: "memo", path: "a.md", old_hash: "abc", new_hash: "def")
      log.append(action: :delete, entry_id: "01A", mode: "memo", path: "a.md", old_hash: "def")

      records = log.read_all
      expect(records.size).to eq(3)
      expect(records.map { |r| r["action"] }).to eq(%w[create update delete])
    end

    it "actor 명시 가능" do
      log.append(action: :adopt, entry_id: "01X", mode: "note", path: "x.md", actor: "filesystem")
      expect(log.read_all.first["actor"]).to eq("filesystem")
    end

    it "허용되지 않는 action 거부" do
      expect {
        log.append(action: :unknown, entry_id: "x", mode: "memo", path: "p")
      }.to raise_error(ArgumentError, /허용되지 않는 action/)
    end

    it "허용되지 않는 actor 거부" do
      expect {
        log.append(action: :create, entry_id: "x", mode: "memo", path: "p", actor: "hacker")
      }.to raise_error(ArgumentError, /허용되지 않는 actor/)
    end

    it ".sowing 디렉토리 자동 생성" do
      expect(tmpdir.join(".sowing")).not_to exist
      log.append(action: :create, entry_id: "x", mode: "memo", path: "p")
      expect(tmpdir.join(".sowing/audit.log")).to exist
    end
  end

  describe ".with_actor (스레드 로컬 actor 스택)" do
    after { Thread.current[:sowing_audit_actor_stack] = nil }

    it "블록 내부에서 default actor override" do
      described_class.with_actor("agent") do
        log.append(action: :create, entry_id: "01A", mode: "memo", path: "a.md")
      end
      expect(log.read_all.first["actor"]).to eq("agent")
    end

    it "중첩 가능 — 안쪽이 우선, 빠져나오면 복원" do
      described_class.with_actor("agent") do
        log.append(action: :create, entry_id: "01A", mode: "memo", path: "a.md")
        described_class.with_actor("filesystem") do
          log.append(action: :reindex, entry_id: "01A", mode: "memo", path: "a.md")
        end
        log.append(action: :update, entry_id: "01A", mode: "memo", path: "a.md")
      end

      actors = log.read_all.map { |r| r["actor"] }
      expect(actors).to eq(%w[agent filesystem agent])
    end

    it "예외 발생 시에도 스택 복원 (ensure)" do
      expect {
        described_class.with_actor("agent") { raise "boom" }
      }.to raise_error("boom")
      expect(described_class.current_actor).to eq("user")
    end
  end

  describe "#read_all" do
    it "파일 없으면 빈 배열" do
      expect(log.read_all).to eq([])
    end

    it "각 줄 JSON 파싱 가능" do
      3.times { |i| log.append(action: :create, entry_id: "01-#{i}", mode: "memo", path: "p#{i}.md") }
      records = log.read_all
      expect(records.size).to eq(3)
      records.each { |r| expect(r).to be_a(Hash) }
    end
  end

  describe "#clear! (테스트 격리용)" do
    it "파일 삭제 후 read_all → 빈 배열" do
      log.append(action: :create, entry_id: "x", mode: "memo", path: "p")
      log.clear!
      expect(log.read_all).to eq([])
    end

    it "파일 없을 때도 안전" do
      expect { log.clear! }.not_to raise_error
    end
  end

  describe "스레드 안전성" do
    it "동시 append 충돌 없음 (mutex)" do
      threads = 5.times.map do |i|
        Thread.new do
          10.times do |j|
            log.append(action: :create, entry_id: "t#{i}-#{j}", mode: "memo", path: "p")
          end
        end
      end
      threads.each(&:join)
      expect(log.read_all.size).to eq(50)
    end
  end
end
