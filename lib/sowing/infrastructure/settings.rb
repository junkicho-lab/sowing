# frozen_string_literal: true

require "json"
require "fileutils"

module Sowing
  module Infrastructure
    # 사용자 설정 저장소 — data_dir/settings.json (W7-T01).
    #
    # 단순 key-value JSON. 동시 쓰기는 가정하지 않음 (단일 사용자 데스크톱 앱).
    # 파일이 없으면 DEFAULTS 반환. 부분 갱신은 update(key:, value:)로.
    #
    # SafeWriter는 의존하지 않음 — 부팅 매우 초기에 로드되는 모듈이라 zeitwerk-loaded
    # 코드를 참조할 수 없는 보수적 가정. JSON·File 표준 라이브러리만 사용.
    module Settings
      DEFAULTS = {
        "onboarding_completed" => false,
        "user_name" => nil,
        "vault_consent" => nil,
        "sample_consent" => nil,
        "completed_at" => nil,
        "tutorial_step" => 1,
        "tutorial_completed_at" => nil
      }.freeze

      module_function

      def path
        Paths.data_dir.join("settings.json")
      end

      def load
        return DEFAULTS.dup unless File.exist?(path)
        DEFAULTS.merge(JSON.parse(File.read(path)))
      rescue JSON::ParserError
        # 손상된 파일은 기본값 반환 (앱 부팅 막지 않음).
        DEFAULTS.dup
      end

      def save(hash)
        FileUtils.mkdir_p(Paths.data_dir)
        merged = DEFAULTS.merge(hash)
        File.write(path, JSON.pretty_generate(merged))
        merged
      end

      def update(**changes)
        current = self.load
        save(current.merge(changes.transform_keys(&:to_s)))
      end

      def reset!
        File.unlink(path) if File.exist?(path)
      end

      def onboarding_completed?
        self.load["onboarding_completed"] == true
      end
    end
  end
end
