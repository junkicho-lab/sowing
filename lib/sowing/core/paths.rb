# frozen_string_literal: true

require "pathname"
require "fileutils"
require "securerandom"

module Sowing
  module Core
    # OS별 표준 경로를 결정하는 헬퍼.
    # Zeitwerk 로드 전에 require 되므로 다른 Sowing 클래스를 참조하지 않음.
    module Paths
      module_function

      # 사용자 볼트 디렉토리 (마크다운 파일이 저장되는 곳).
      # 환경변수 SOWING_VAULT 가 있으면 그것을, 없으면 OS별 기본값.
      def vault_dir
        Pathname.new(ENV.fetch("SOWING_VAULT") { default_vault_dir })
      end

      def default_vault_dir
        File.expand_path("~/Documents/SowingVault")
      end

      # 앱 데이터 디렉토리 (SQLite, 로그 등).
      def data_dir
        Pathname.new(ENV.fetch("SOWING_DATA_DIR") { default_data_dir })
      end

      def default_data_dir
        case host_os
        when :macos
          File.expand_path("~/Library/Application Support/Sowing")
        when :windows
          File.join(ENV.fetch("APPDATA"), "Sowing")
        else
          File.expand_path("~/.local/share/sowing")
        end
      end

      def db_path
        data_dir.join("index.sqlite3").to_s
      end

      def log_path
        data_dir.join("sowing.log").to_s
      end

      def session_secret
        path = data_dir.join("session.secret")
        return File.read(path).chomp if File.exist?(path)

        secret = SecureRandom.hex(32)
        FileUtils.mkdir_p(data_dir)
        File.write(path, secret)
        File.chmod(0o600, path)
        secret
      end

      def ensure_data_dirs!
        FileUtils.mkdir_p(data_dir)
        FileUtils.mkdir_p(vault_dir)
      end

      def host_os
        case RUBY_PLATFORM
        when /darwin/ then :macos
        when /mingw|mswin|cygwin/ then :windows
        else :linux
        end
      end
    end
  end
end
