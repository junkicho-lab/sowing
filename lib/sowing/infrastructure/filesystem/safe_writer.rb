# frozen_string_literal: true

require "fileutils"
require "pathname"
require "securerandom"

module Sowing
  module Infrastructure
    module Filesystem
      # 원자적 파일 쓰기 + 한글 파일명 NFC 정규화.
      #
      # 직접 File.write 대신 항상 본 클래스를 거쳐야 한다 (CLAUDE.md 원칙 5).
      #
      # 보장:
      #   - 쓰기 도중 강제 종료(예외·Interrupt)되어도 대상 파일은 손상되지 않는다.
      #     (POSIX rename(2)이 원자적이므로, 기존 내용 유지 또는 완전한 새 내용 — 중간 상태 없음.)
      #   - 한글 파일명은 NFC로 정규화되어 저장된다 (macOS·Windows·Linux 일관성).
      #   - 실패 시 tempfile은 정리된다 (ensure 블록).
      #   - 디스크에 fsync 수행 후 rename → 파워 컷에도 데이터 보존성 향상.
      class SafeWriter
        def initialize(registry: SelfWriteRegistry.instance)
          @registry = registry
        end

        # 파일을 원자적으로 쓴다.
        #
        # @param path    [String, Pathname] 대상 경로 (절대 경로 권장)
        # @param content [String]            파일 내용 (UTF-8 가정)
        # @param mode    [Integer]           파일 권한 (기본 0644)
        # @return        [Pathname]          NFC 정규화 적용된 실제 쓰기 경로
        # @raise [SystemCallError]           디스크·권한 등 OS 레벨 에러는 그대로 전파
        def atomic_write(path, content, mode: 0o644)
          path = Pathname.new(path.to_s.unicode_normalize(:nfc))
          FileUtils.mkdir_p(path.dirname)

          tmp_path = tempfile_path(path)

          begin
            write_and_sync(tmp_path, content)
            File.chmod(mode, tmp_path)
            # FileWatcher가 자기 자신의 쓰기를 무시하도록 — rename 직전 등록 (race 방지).
            @registry.register(path)
            File.rename(tmp_path, path)
            fsync_directory(path.dirname)
          ensure
            cleanup(tmp_path)
          end

          path
        end

        private

        # 같은 디렉토리에 임시 파일 생성 (rename 원자성은 동일 파일시스템에서만 보장).
        # 파일명 형식: ".<basename>.tmp.<random hex>" — 점 prefix로 숨김 처리.
        def tempfile_path(target)
          target.dirname.join(".#{target.basename}.tmp.#{SecureRandom.hex(8)}")
        end

        def write_and_sync(path, content)
          File.open(path, "wb") do |f|
            f.write(content)
            f.flush
            f.fsync
          end
        end

        # 디렉토리 메타데이터(파일 추가 사실) 자체를 디스크에 동기화.
        # 일부 플랫폼(Windows 등)은 디렉토리 fsync를 지원하지 않을 수 있으므로 안전하게 무시.
        def fsync_directory(dir)
          File.open(dir) { |d| d.fsync }
        rescue SystemCallError, NotImplementedError
          # 무시: 디렉토리 fsync 미지원 플랫폼
        end

        def cleanup(tmp_path)
          File.unlink(tmp_path) if File.exist?(tmp_path)
        end
      end
    end
  end
end
