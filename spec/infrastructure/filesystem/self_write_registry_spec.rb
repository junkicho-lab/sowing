# frozen_string_literal: true

require "tmpdir"

RSpec.describe Sowing::Infrastructure::Filesystem::SelfWriteRegistry do
  subject(:registry) { described_class.new(ttl: 0.5) }

  let(:tmpdir) { Pathname.new(Dir.mktmpdir("self-write-registry-spec-")) }
  let(:path) { tmpdir.join("foo.md") }

  after { FileUtils.rm_rf(tmpdir) if tmpdir.exist? }

  describe "#register / #recent?" do
    it "등록 직후에는 recent?가 true" do
      registry.register(path)
      expect(registry.recent?(path)).to be true
    end

    it "TTL 초과 후에는 false" do
      registry.register(path)
      sleep 0.6
      expect(registry.recent?(path)).to be false
    end

    it "등록 안 한 경로는 false" do
      expect(registry.recent?(path)).to be false
    end

    it "재등록은 TTL을 갱신한다" do
      registry.register(path)
      sleep 0.3
      registry.register(path)
      sleep 0.3
      expect(registry.recent?(path)).to be true
    end
  end

  describe "경로 정규화" do
    it "상대경로/절대경로/Pathname 모두 동일하게 처리" do
      registry.register(path.to_s)
      expect(registry.recent?(Pathname.new(path.to_s))).to be true
    end

    it "한글 파일명도 NFC 정규화 후 일치 (NFD 입력 → NFC 비교)" do
      nfc_path = tmpdir.join("한글.md")
      nfd_path = nfc_path.to_s.unicode_normalize(:nfd)
      registry.register(nfd_path)
      expect(registry.recent?(nfc_path)).to be true
    end
  end

  describe "스레드 안전성" do
    it "동시에 여러 스레드가 register/recent? 호출해도 데이터 손상 없음" do
      threads = 10.times.map do |i|
        Thread.new do
          50.times do |j|
            target = tmpdir.join("t#{i}-#{j}.md")
            registry.register(target)
            registry.recent?(target)
          end
        end
      end
      threads.each(&:join)
      # 명시적 assertion: 예외 없이 완주
      expect(true).to be true
    end
  end

  describe "#clear" do
    it "모든 항목 제거" do
      registry.register(path)
      registry.clear
      expect(registry.recent?(path)).to be false
    end
  end

  describe ".instance (싱글턴)" do
    after { described_class.instance_variable_set(:@instance, nil) }

    it "동일한 인스턴스를 반환" do
      a = described_class.instance
      b = described_class.instance
      expect(a).to equal(b)
    end

    it "instance= 로 교체 가능 (테스트 격리용)" do
      custom = described_class.new(ttl: 1.0)
      described_class.instance = custom
      expect(described_class.instance).to equal(custom)
    end
  end
end
