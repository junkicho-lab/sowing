# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Sowing::Sync::Coordinator do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("coordinator-spec-")) }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:db) { Sowing::Infrastructure::DB.connection }

  let(:coordinator) do
    described_class.new(
      vault_dir: vault_dir,
      vault_repo: vault_repo,
      index_repo: index_repo,
      watcher_factory: ->(dir, on_change) {
        Sowing::Infrastructure::Filesystem::FileWatcher.new(
          vault_dir: dir, on_change: on_change, latency: 0.05, force_polling: true
        )
      }
    )
  end

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after do
    coordinator.stop if coordinator.running?
    FileUtils.rm_rf(vault_dir) if vault_dir.exist?
  end

  def create_note
    Sowing::UseCases::CreateNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
      title: "동기화 테스트", body: "본문", category: "lessons", source: "교과서"
    ).value!
  end

  describe "#handle_event (직접 호출 — 단위)" do
    it ":modified 이벤트 → ReindexEntry 호출 + 결과 반환" do
      note = create_note
      abs = vault_dir.join(index_repo.find(note.id).path)
      File.write(abs, abs.read.sub("본문", "외부 수정"))
      sleep 1.1

      result = coordinator.handle_event(type: :modified, path: abs)
      expect(result).to be_success
      expect(result.value!).to eq(:reindexed)
    end

    it "예외 발생 시 Failure([:exception, msg]) — watcher 스레드 죽지 않음" do
      bad_event = {type: :modified} # path 없음 → KeyError
      result = coordinator.handle_event(bad_event)
      expect(result).to be_failure
      expect(result.failure.first).to eq(:exception)
    end
  end

  describe "#subscribe / 이벤트 통지" do
    it "구독자에게 event + result 전달" do
      received = []
      coordinator.subscribe { |event:, result:| received << [event[:type], result.value!] }

      note = create_note
      abs = vault_dir.join(index_repo.find(note.id).path)
      coordinator.handle_event(type: :modified, path: abs)

      expect(received).to eq([[:modified, :unchanged]])
    end

    it "여러 구독자 모두 호출" do
      counts = [0, 0]
      coordinator.subscribe { |**| counts[0] += 1 }
      coordinator.subscribe { |**| counts[1] += 1 }

      note = create_note
      abs = vault_dir.join(index_repo.find(note.id).path)
      coordinator.handle_event(type: :modified, path: abs)

      expect(counts).to eq([1, 1])
    end

    it "한 구독자가 raise해도 다른 구독자는 호출됨" do
      called = false
      coordinator.subscribe { |**| raise "boom" }
      coordinator.subscribe { |**| called = true }

      note = create_note
      abs = vault_dir.join(index_repo.find(note.id).path)
      expect { coordinator.handle_event(type: :modified, path: abs) }.not_to raise_error
      expect(called).to be true
    end

    it "unsubscribe 후에는 호출 안 됨" do
      received = []
      handle = coordinator.subscribe { |**| received << :tick }
      coordinator.unsubscribe(handle)

      note = create_note
      abs = vault_dir.join(index_repo.find(note.id).path)
      coordinator.handle_event(type: :modified, path: abs)
      expect(received).to be_empty
    end
  end

  describe "#start / #stop (watcher 통합)" do
    it "start 후 외부 변경 감지 → 인덱스 자동 갱신" do
      note = create_note
      abs = vault_dir.join(index_repo.find(note.id).path)
      original_mtime = index_repo.find(note.id).file_mtime

      results = []
      coordinator.subscribe { |result:, **| results << result.value! }
      coordinator.start

      sleep 0.2 # 폴링 watcher가 baseline 잡을 시간
      sleep 1.1 # mtime 1초 단위 보장
      # CreateNote가 self-write로 등록한 항목 제거 — 이후 변경은 "외부 편집"으로 간주.
      Sowing::Infrastructure::Filesystem::SelfWriteRegistry.instance.clear
      File.write(abs, abs.read.sub("본문", "외부 변경"))

      # 폴링 모드는 변경/추가 구분이 불완전하므로 둘 다 허용 — 핵심은 인덱스 갱신.
      deadline = Time.now + 5
      until (results & %i[reindexed added]).any? || Time.now > deadline
        sleep 0.05
      end

      expect(results).to include(:reindexed).or include(:added)
      expect(index_repo.find(note.id).file_mtime).to be > original_mtime
    end

    it "running? 상태 전이" do
      expect(coordinator.running?).to be false
      coordinator.start
      expect(coordinator.running?).to be true
      coordinator.stop
      expect(coordinator.running?).to be false
    end

    it "이중 start는 idempotent" do
      coordinator.start
      expect { coordinator.start }.not_to raise_error
    end
  end
end
