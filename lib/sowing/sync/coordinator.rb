# frozen_string_literal: true

module Sowing
  module Sync
    # FileWatcher → ReindexEntry 파이프라인 + 구독자 브로드캐스트 (W5-T02).
    #
    # 책임:
    #   - 앱 부팅 시 watcher 시작, 종료 시 중단
    #   - 변경 이벤트마다 ReindexEntry 호출 + 결과를 구독자에게 통지
    #   - 구독자(SSE 푸시·로깅 등)는 subscribe(&block)으로 등록
    #
    # 인덱스 갱신 자체는 ReindexEntry가 책임지므로 본 클래스는 얇은 코디네이터.
    # handle_event는 watcher 우회 직접 호출도 가능 — 단위 테스트와 부팅 시 일관성 검증(T04)에 활용.
    class Coordinator
      def initialize(vault_dir:,
        vault_repo: nil,
        index_repo: nil,
        watcher_factory: nil,
        logger: nil,
        adoption_enabled: true)
        @vault_dir = vault_dir
        @vault_repo = vault_repo || Repositories::VaultRepo.new(vault_dir: vault_dir)
        @index_repo = index_repo || Repositories::IndexRepo.new
        @reindex = UseCases::ReindexEntry.new(vault_repo: @vault_repo, index_repo: @index_repo)
        @adopt = UseCases::AdoptOrphan.new(vault_repo: @vault_repo, index_repo: @index_repo)
        @adoption_enabled = adoption_enabled
        @watcher_factory = watcher_factory || method(:default_watcher)
        @logger = logger
        @subscribers = []
        @subscribers_mutex = Mutex.new
        @watcher = nil
      end

      def start
        return self if @watcher&.running?
        @watcher = @watcher_factory.call(@vault_dir, ->(event) { handle_event(event) })
        @watcher.start
        self
      end

      def stop
        @watcher&.stop
        @watcher = nil
        self
      end

      def running?
        !@watcher.nil? && @watcher.running?
      end

      # 구독: 모든 이벤트 처리 결과를 받는다.
      # block은 keyword args(event:, result:)로 호출됨.
      # @return [Proc] unsubscribe 식별자
      def subscribe(&block)
        @subscribers_mutex.synchronize { @subscribers << block }
        block
      end

      def unsubscribe(block)
        @subscribers_mutex.synchronize { @subscribers.delete(block) }
      end

      # 외부에서 직접 호출 가능 — 부팅 시 일관성 검증(W5-T04)에서도 사용.
      # frontmatter 누락 파일은 adoption_enabled일 때 AdoptOrphan으로 fallback (W5-T03).
      def handle_event(event)
        result = @reindex.call(event)
        result = adopt_if_orphan(event, result) if should_attempt_adoption?(result)
        notify(event: event, result: result)
        result
      rescue => e
        @logger&.error("[Sync::Coordinator] #{e.class}: #{e.message}")
        Dry::Monads::Failure([:exception, e.message])
      end

      private

      def should_attempt_adoption?(result)
        @adoption_enabled &&
          result.failure? &&
          result.failure.is_a?(Array) &&
          result.failure.first == :invalid_frontmatter
      end

      def adopt_if_orphan(event, reindex_result)
        adopt_result = @adopt.call(event)
        adopt_result.success? ? Dry::Monads::Success(:adopted) : reindex_result
      end

      def default_watcher(vault_dir, on_change)
        Infrastructure::Filesystem::FileWatcher.new(vault_dir: vault_dir, on_change: on_change)
      end

      def notify(payload)
        snapshot = @subscribers_mutex.synchronize { @subscribers.dup }
        snapshot.each do |sub|
          sub.call(**payload)
        rescue => e
          @logger&.error("[Sync::Coordinator subscriber] #{e.class}: #{e.message}")
        end
      end
    end
  end
end
