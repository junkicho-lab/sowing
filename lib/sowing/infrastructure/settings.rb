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
        "tutorial_completed_at" => nil,
        "class_roster" => [], # W17-T03: 학급 명단 (학생 이름 배열). GapDetector 의 입력.
        # Phase 13 W25-T02: 동사 중심 nav 변경 안내 모달 1회 표시. 사용자가 'X' 또는
        # '이해했습니다' 클릭 시 ISO8601 timestamp 기록. nil 이면 다음 진입 시 모달 표시.
        "ia_v2_seen_at" => nil
      }.freeze

      module_function

      def path
        Paths.data_dir.join("settings.json")
      end

      def load
        return DEFAULTS.dup unless File.exist?(path)
        # encoding: "UTF-8" 명시 — LANG 미설정 GUI 컨텍스트(예: Sowing.app 더블클릭,
        # 일부 cron 환경) 에서 File.read 가 US-ASCII 로 읽어 한글 settings 깨짐 방지.
        DEFAULTS.merge(JSON.parse(File.read(path, encoding: "UTF-8")))
      rescue JSON::ParserError, Encoding::InvalidByteSequenceError
        # 손상된 파일 또는 인코딩 오류 → 기본값 반환 (앱 부팅 막지 않음).
        DEFAULTS.dup
      end

      def save(hash)
        FileUtils.mkdir_p(Paths.data_dir)
        merged = DEFAULTS.merge(hash)
        # 한글 학생 이름 등이 깨지지 않도록 UTF-8 명시 (NFC 정규화는 호출 측 책임).
        File.write(path, JSON.pretty_generate(merged), encoding: "UTF-8")
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
