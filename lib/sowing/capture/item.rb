# frozen_string_literal: true

module Sowing
  module Capture
    # Capture::Item — 즉시 포착 (옛 Domain::Memo 의 후신, ADR-019).
    #
    # 비전 D.1 — "글쓰기": 떠오르는 즉시 부담 없이 기록.
    # Memo 와의 차이:
    #   - subject 4축 (person/subject/document/identity, ADR-016) 선택적 부착 가능
    #     → 수집 단계에서 의식적 분류를 권장하되 강제하지 않음 (인지 부담 최소화)
    #   - mode 는 :memo 유지 — Strangler Fig 호환, 옵시디언 파일·DB 무변경
    #     Stage 5 (Note 폐지) 이후에도 capture_item ↔ memo 동의어 관계 유지
    #
    # 파일 매핑: 00_Inbox/{timestamp}.md (옛 Memo 와 동일 디렉토리)
    # 의존: Sowing::Domain::Entry (mixin), Sowing::Domain::ValueObjects::*
    #
    # 불변성: 생성 후 모든 attr frozen. 변경 시 새 인스턴스 생성.
    class Item
      include Sowing::Domain::Entry

      MODE = :memo

      # ADR-016 — Subject 4축 (필수 명시 분류).
      # 자유 카테고리 (category 필드) 와 공존하지만, 4축은 ENUM 으로 일관 보장.
      SUBJECTS = %i[person subject document identity].freeze

      # 4축 ENUM → 한국어 표시 라벨 (2026-05-12 추가).
      # UI 칩 라벨·자동 태그·영구 기록 카테고리에 일관 사용.
      SUBJECT_LABELS = {
        person: "인물",
        subject: "교과",
        document: "문서",
        identity: "정체성"
      }.freeze

      # 카테고리 자유 텍스트 허용에서 4축 한국어 라벨로 제한 (2026-05-12).
      # Knowledge::Record 의 category 도 본 ENUM 만 사용.
      CATEGORY_LABELS = SUBJECT_LABELS.values.freeze

      attr_reader :id, :body, :tags, :title, :template, :subject,
        :created_at, :updated_at

      def initialize(id:, body:, created_at:,
        title: nil, tags: Sowing::Domain::ValueObjects::TagSet.new,
        template: nil, subject: nil, updated_at: nil)
        validate_ulid!(id, :id)
        validate_string!(body, :body)
        validate_tag_set!(tags)
        validate_time!(created_at, :created_at)
        validate_optional_string!(title, :title)
        validate_optional_string!(template, :template)
        validate_optional_subject!(subject)
        updated_at ||= created_at
        validate_time!(updated_at, :updated_at)

        @id = id
        @body = body.freeze
        @tags = tags
        @title = title&.freeze
        @template = template&.freeze
        @subject = subject # Symbol, 이미 frozen
        @created_at = created_at
        @updated_at = updated_at
        freeze
      end

      def mode
        MODE
      end

      def to_frontmatter
        # subject 가 nil 이면 .compact 로 제외됨 — 옛 Memo 파일 구조와 호환
        common_frontmatter.merge("subject" => subject&.to_s).compact
      end

      private

      # subject 는 nil 또는 SUBJECTS 4축 Symbol 중 하나여야 함.
      def validate_optional_subject!(value)
        return if value.nil?
        return if SUBJECTS.include?(value)
        raise ArgumentError,
          "subject 는 #{SUBJECTS.inspect} 중 하나여야 합니다 (받은 값: #{value.inspect})"
      end
    end
  end
end
