# frozen_string_literal: true

require "listen"
require "pathname"

module Sowing
  module Core
    module Filesystem
      # 옵시디언·외부 에디터의 볼트 변경 감지 watcher (W5-T01).
      #
      # Listen gem으로 .md 파일만 감시. 자체 쓰기(SafeWriter / VaultRepo#delete)는
      # SelfWriteRegistry로 필터링 — 자기 자신의 쓰기를 외부 변경으로 오인하지 않는다.
      #
      # 백그라운드 스레드는 Listen이 내부적으로 관리. start/stop으로 제어.
      #
      # 사용:
      #   watcher = FileWatcher.new(vault_dir: ..., on_change: ->(event) { ... })
      #   watcher.start
      #   ...
      #   watcher.stop
      #
      # on_change 콜백 인자:
      #   { type: :modified | :added | :removed, path: Pathname (절대) }
      class FileWatcher
        DEFAULT_LATENCY = 0.5
        # Listen ignore: .sowing/ 디렉토리(휴지통, 내부 메타) 제외.
        IGNORED_PATTERNS = [%r{(^|/)\.sowing(/|$)}].freeze
        ONLY_MARKDOWN = /\.md\z/

        attr_reader :vault_dir

        def initialize(vault_dir:,
          on_change:,
          registry: SelfWriteRegistry.instance,
          latency: DEFAULT_LATENCY,
          force_polling: false)
          @vault_dir = Pathname.new(vault_dir.to_s).expand_path
          @on_change = on_change
          @registry = registry
          @latency = latency
          @force_polling = force_polling
          @listener = nil
        end

        def start
          return if running?
          @listener = build_listener
          @listener.start
          self
        end

        def stop
          @listener&.stop
          @listener = nil
          self
        end

        def running?
          !@listener.nil? && @listener.processing?
        end

        private

        def build_listener
          opts = {
            only: ONLY_MARKDOWN,
            ignore: IGNORED_PATTERNS,
            latency: @latency
          }
          opts[:force_polling] = true if @force_polling

          Listen.to(@vault_dir.to_s, **opts) do |modified, added, removed|
            dispatch(modified, :modified)
            dispatch(added, :added)
            dispatch(removed, :removed)
          end
        end

        def dispatch(paths, type)
          paths.each do |raw|
            next if @registry.recent?(raw)
            @on_change.call(type: type, path: Pathname.new(raw))
          end
        end
      end
    end
  end
end
