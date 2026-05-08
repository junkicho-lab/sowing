# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "timeout"

RSpec.describe Sowing::Infrastructure::Filesystem::FileWatcher do
  # Listen은 비동기. 테스트는 짧은 latency + 폴링으로 안정화.
  let(:watcher_latency) { 0.05 }
  let(:wait_timeout) { 5.0 }

  let(:tmpdir) { Pathname.new(Dir.mktmpdir("file-watcher-spec-")) }
  let(:registry) { Sowing::Infrastructure::Filesystem::SelfWriteRegistry.new(ttl: 2.0) }
  let(:events) { [] }
  let(:events_mutex) { Mutex.new }

  let(:on_change) do
    ->(event) { events_mutex.synchronize { events << event } }
  end

  let(:watcher) do
    described_class.new(
      vault_dir: tmpdir,
      on_change: on_change,
      registry: registry,
      latency: watcher_latency,
      force_polling: true # macOS fsevents는 latency floor·심볼릭 링크 이슈로 테스트 불안정 → 폴링 모드.
    )
  end

  after do
    watcher.stop if watcher.running?
    FileUtils.rm_rf(tmpdir) if tmpdir.exist?
  end

  def collected_events
    events_mutex.synchronize { events.dup }
  end

  def wait_for_event(timeout: wait_timeout)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield(collected_events)
      raise "timeout waiting for event (got #{collected_events.size}: #{collected_events.inspect})" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
  end

  describe "외부 변경 감지" do
    it "신규 .md 파일 생성 → :added 이벤트" do
      watcher.start
      target = tmpdir.join("new.md")
      File.write(target, "외부 에디터 작성")

      wait_for_event { |evs| evs.any? { |e| e[:type] == :added && e[:path].basename.to_s == "new.md" } }
    end

    it "기존 .md 파일 수정 → :modified 이벤트" do
      target = tmpdir.join("existing.md")
      File.write(target, "원본")
      watcher.start
      sleep 0.2 # Listen이 baseline 스냅샷 잡을 시간

      File.write(target, "외부 수정")
      wait_for_event { |evs| evs.any? { |e| e[:type] == :modified && e[:path].basename.to_s == "existing.md" } }
    end

    it ".md 외 파일은 무시 (only filter)" do
      watcher.start
      File.write(tmpdir.join("note.txt"), "텍스트 파일")
      File.write(tmpdir.join("trigger.md"), "마크다운")

      wait_for_event { |evs| evs.any? { |e| e[:path].basename.to_s == "trigger.md" } }
      expect(collected_events.map { |e| e[:path].basename.to_s }).not_to include("note.txt")
    end

    it ".sowing/ 디렉토리는 무시 (휴지통 등)" do
      sowing_dir = tmpdir.join(".sowing/trash")
      FileUtils.mkdir_p(sowing_dir)
      watcher.start

      File.write(sowing_dir.join("trashed.md"), "휴지통")
      File.write(tmpdir.join("normal.md"), "정상")

      wait_for_event { |evs| evs.any? { |e| e[:path].basename.to_s == "normal.md" } }
      expect(collected_events.map { |e| e[:path].basename.to_s }).not_to include("trashed.md")
    end
  end

  describe "self-write 필터" do
    it "registry에 등록된 경로의 변경 이벤트는 콜백 호출 안 함" do
      target = tmpdir.join("self.md")
      File.write(target, "초기")
      watcher.start
      sleep 0.2

      registry.register(target)
      File.write(target, "내가 쓴 변경")

      sleep watcher_latency + 0.5
      paths = collected_events.map { |e| e[:path].basename.to_s }
      expect(paths).not_to include("self.md")
    end

    it "TTL 만료 후 같은 경로 변경은 다시 통지 (외부 편집으로 간주)" do
      short_registry = Sowing::Infrastructure::Filesystem::SelfWriteRegistry.new(ttl: 0.1)
      short_watcher = described_class.new(
        vault_dir: tmpdir,
        on_change: on_change,
        registry: short_registry,
        latency: watcher_latency,
        force_polling: true
      )
      target = tmpdir.join("ttl.md")
      File.write(target, "초기")
      short_watcher.start
      sleep 0.2

      short_registry.register(target)
      sleep 0.3 # TTL 초과 대기
      File.write(target, "외부 편집")

      begin
        wait_for_event(timeout: 3.0) { |evs| evs.any? { |e| e[:path].basename.to_s == "ttl.md" } }
      ensure
        short_watcher.stop
      end
    end
  end

  describe "lifecycle" do
    it "start 전에는 running? false" do
      expect(watcher.running?).to be false
    end

    it "start → running? true → stop → false" do
      watcher.start
      expect(watcher.running?).to be true
      watcher.stop
      expect(watcher.running?).to be false
    end

    it "이중 start는 무시 (idempotent)" do
      watcher.start
      expect { watcher.start }.not_to raise_error
      expect(watcher.running?).to be true
    end

    it "start 안 한 상태로 stop은 에러 없음" do
      expect { watcher.stop }.not_to raise_error
    end
  end
end
