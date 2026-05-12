# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "time"

module Sowing
  module Core
    # 모든 entry mutation 의 구조화 로그 (W9-T01).
    #
    # 형식: JSON Lines (한 줄 = 하나의 mutation 이벤트). `.sowing/audit.log` 에
    # append-only 로 기록. 절대 수정·삭제 안 함 (감사 추적 무결성).
    #
    # 스키마:
    #   {ts, actor, action, entry_id, mode, path, old_hash, new_hash}
    #
    # actor: "user" | "agent" | "filesystem"
    #   - "user": 웹 UI / CLI 직접 호출
    #   - "agent": MCP 서버 등 외부 에이전트 (W9-T03+)
    #   - "filesystem": 외부 에디터(옵시디언) 변경을 watcher 가 동기화한 경우
    # action: :create | :update | :delete | :adopt | :reindex
    # path: vault 기준 상대경로 (절대경로 노출 안 해 portability + privacy)
    # old_hash / new_hash: SHA-256 16-hex prefix. create 는 old=nil, delete 는 new=nil.
    #
    # 스레드 안전: 단일 mutex 로 파일 append 보호. Coordinator·watcher 가 별도 스레드
    # 에서 audit 호출하는 시나리오 대비.
    #
    # Phase 9-T03 (MCP 쓰기 actuator) 에서 actor="agent" 활용. Phase 11+ 합성
    # 산출물의 수락/거절도 audit 으로 기록 (preference data).
    class AuditLog
      # Phase 11+ synth_* — 합성기 생성·수락·거절 (Phase 11~12 fine-tuning preference 데이터).
      ALLOWED_ACTIONS = %i[create update delete adopt reindex synth_generate synth_accept synth_reject].freeze
      ALLOWED_ACTORS = %w[user agent filesystem].freeze

      class << self
        def instance
          @instance ||= new
        end

        # 테스트 격리용. 또는 다른 vault_dir 가 필요할 때.
        attr_writer :instance

        # actor 를 일시적으로 override — MCP 서버가 본 블록 안에서 use case 를 호출.
        # 중첩 가능 (스택). default 는 "user".
        def with_actor(actor)
          raise ArgumentError, "지원하지 않는 actor: #{actor.inspect}" unless ALLOWED_ACTORS.include?(actor.to_s)
          stack = Thread.current[:sowing_audit_actor_stack] ||= []
          stack.push(actor.to_s)
          yield
        ensure
          stack&.pop
        end

        def current_actor
          Thread.current[:sowing_audit_actor_stack]&.last || "user"
        end
      end

      def initialize(vault_dir: nil, clock: Time)
        @vault_dir_override = vault_dir
        @clock = clock
        @mutex = Mutex.new
      end

      def path
        vault_dir.join(".sowing/audit.log")
      end

      # 한 줄 추가. 호출자는 keyword argument 로 모든 필드 명시.
      # @return [Hash] 기록된 record (테스트·디버깅용)
      def append(action:, entry_id:, mode:, path:, actor: nil, old_hash: nil, new_hash: nil)
        validate_action!(action)
        actor ||= self.class.current_actor
        validate_actor!(actor)

        record = {
          ts: @clock.now.iso8601,
          actor: actor.to_s,
          action: action.to_s,
          entry_id: entry_id.to_s,
          mode: mode.to_s,
          path: path.to_s,
          old_hash: old_hash,
          new_hash: new_hash
        }

        write_line(record)
        record
      end

      # 모든 record 를 Hash 배열로 (테스트·진단용). 큰 로그에선 사용 자제.
      def read_all
        return [] unless path.exist?
        path.each_line.map { |line| JSON.parse(line) }
      end

      # 테스트 격리용. 프로덕션에선 호출 금지 (감사 추적 무결성).
      def clear!
        @mutex.synchronize do
          File.unlink(path) if path.exist?
        end
      end

      private

      def vault_dir
        @vault_dir_override ? Pathname.new(@vault_dir_override.to_s).expand_path : Paths.vault_dir
      end

      def validate_action!(action)
        return if ALLOWED_ACTIONS.include?(action.to_sym)
        raise ArgumentError, "허용되지 않는 action: #{action.inspect} (#{ALLOWED_ACTIONS.inspect})"
      end

      def validate_actor!(actor)
        return if ALLOWED_ACTORS.include?(actor.to_s)
        raise ArgumentError, "허용되지 않는 actor: #{actor.inspect} (#{ALLOWED_ACTORS.inspect})"
      end

      def write_line(record)
        @mutex.synchronize do
          FileUtils.mkdir_p(path.dirname)
          File.open(path, "a") do |f|
            f.puts(JSON.generate(record))
            f.fsync
          end
        end
      end
    end
  end
end
