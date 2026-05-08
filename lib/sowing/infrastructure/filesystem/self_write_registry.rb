# frozen_string_literal: true

require "pathname"

module Sowing
  module Infrastructure
    module Filesystem
      # 자체 쓰기 추적용 TTL 레지스트리.
      #
      # FileWatcher가 자기 자신의 쓰기(SafeWriter, VaultRepo#delete 경유)를
      # 외부 변경 이벤트로 잘못 감지하지 않도록 필터링하는 데 쓰인다.
      #
      # 사용 흐름:
      #   1. SafeWriter#atomic_write → 파일 쓰기 직전 register(path)
      #   2. Listen이 변경 이벤트 emit
      #   3. FileWatcher가 recent?(path) 체크 — true면 콜백 호출 생략
      #
      # 스레드 안전: Listen은 별도 스레드에서 콜백을 부른다.
      # TTL: 2초면 충분 — 쓰기→fsync→rename→Listen latency(0.5s)를 모두 커버.
      class SelfWriteRegistry
        TTL_SECONDS = 2.0

        def self.instance
          @instance ||= new
        end

        # 테스트 격리용 — 글로벌 인스턴스를 교체할 수 있다.
        def self.instance=(registry)
          @instance = registry
        end

        def initialize(ttl: TTL_SECONDS)
          @ttl = ttl
          @entries = {} # NFC 절대경로 String → 만료 monotonic time
          @mutex = Mutex.new
        end

        def register(path)
          abs = normalize(path)
          @mutex.synchronize do
            @entries[abs] = monotonic + @ttl
            cleanup_expired
          end
          abs
        end

        def recent?(path)
          abs = normalize(path)
          @mutex.synchronize do
            expiry = @entries[abs]
            return false if expiry.nil?
            if monotonic <= expiry
              true
            else
              @entries.delete(abs)
              false
            end
          end
        end

        def clear
          @mutex.synchronize { @entries.clear }
        end

        private

        # macOS는 /var → /private/var 심볼릭 링크 — Listen은 realpath로 emit하므로
        # 등록·조회 모두 realpath로 일관되게 정규화한다.
        # 파일이 아직 없을 때(예: rename 직전 register)는 dirname#realpath + basename으로 해결.
        def normalize(path)
          pn = Pathname.new(path.to_s.unicode_normalize(:nfc)).expand_path
          if pn.exist?
            pn.realpath.to_s
          elsif pn.dirname.exist?
            pn.dirname.realpath.join(pn.basename).to_s
          else
            pn.to_s
          end
        end

        def cleanup_expired
          now = monotonic
          @entries.delete_if { |_, expiry| expiry < now }
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
