# frozen_string_literal: true

module Sowing
  # Bounded Context #1 — Capture (포착·즉시 기록).
  #
  # 책임: 비전 D.1 ("글쓰기") 의 즉시 포착 - 떠오르는 즉시 부담 없이 기록.
  # 4 모듈 의존 그래프의 base — 다른 모듈 의존 0.
  #
  # 도메인:
  #   - Capture::Item — 옛 Domain::Memo 의 후신 (subject 4축 + body, R2-T01)
  #   - Capture::ItemRepo — 영속화 어댑터 (R2-T02)
  #
  # 외부 인터페이스 (Façade) — 다른 모듈은 본 메서드들만 사용. 내부 클래스
  # 직접 참조 금지 (bin/sowing-arch-check 가 검증).
  #
  # 의존: Core 만.
  module Capture
    @repo_mutex = Mutex.new

    class << self
      # 단일 Item 생성 (파일 + 인덱스).
      # @param body [String] 본문 (필수, 빈 문자열 불가)
      # @param subject [Symbol, nil] Item::SUBJECTS 4축 중 하나
      # @param title [String, nil]
      # @param tags [Array<String>, TagSet]
      # @param template [String, nil]
      # @param id [Sowing::Domain::ValueObjects::Ulid, nil] (테스트 주입용)
      # @param created_at [Time, nil] (테스트 주입용)
      # @return [Sowing::Capture::Item]
      # @raise [ArgumentError] body 가 빈 문자열일 때
      def create_item(body:, subject: nil, title: nil, tags: [], template: nil,
        id: nil, created_at: nil)
        raise ArgumentError, "body 는 빈 문자열일 수 없습니다" if body.to_s.strip.empty?

        item = Item.new(
          id: id || Domain::ValueObjects::Ulid.generate,
          body: body,
          created_at: created_at || Time.now,
          title: title,
          tags: tags.is_a?(Domain::ValueObjects::TagSet) ? tags : Domain::ValueObjects::TagSet.new(tags),
          template: template,
          subject: subject
        )
        repo.create(item)
      end

      # @return [Sowing::Capture::Item, nil]
      def find(id)
        repo.find(id)
      end

      # @return [Array<Sowing::Capture::Item>]
      def recent(limit: 10)
        repo.recent(limit: limit)
      end

      # ItemRepo 진입점 — 캐싱하여 부팅 비용 분산.
      def repo
        @repo_mutex.synchronize { @repo ||= ItemRepo.new }
      end

      # 테스트 격리용 — 임시 repo 주입.
      attr_writer :repo

      # 테스트 격리용 — 캐시 리셋.
      def reset_repo!
        @repo_mutex.synchronize { @repo = nil }
      end
    end
  end
end
