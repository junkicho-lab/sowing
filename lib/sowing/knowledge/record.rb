# frozen_string_literal: true

module Sowing
  module Knowledge
    # Knowledge::Record — Note + Record 흡수 (ADR-015) + 4축 (ADR-016) 도메인.
    #
    # ADR-015 배경: 옛 Note 와 Record 는 의도 차이 (외부 자료 정리 vs 자기 경험·통찰)
    # 만 있었고 구조가 거의 동일. Note 의 source 만 unique. UI 분기·사용자 혼란 가중.
    # 통합 Knowledge::Record 가 source 도 optional 보유 → 표현력 손실 없이 모델 단순화.
    #
    # ADR-016 배경: subject 4축 (person/subject/document/identity) 명시 분류.
    # 옛 free-text category 와 공존하지만 4축은 ENUM 으로 일관 보장.
    #
    # 파일 매핑: 30_Records/{YYYY}/{category}/{title|timestamp}.md
    # 옵시디언 호환 — Note 의 20_Notes/ 는 Stage 5 마이그레이션에서 30_Records/ 로 이전.
    #
    # 의존: Domain::Entry (mixin), Domain::ValueObjects::*, Capture::Item (SUBJECTS 재사용)
    #
    # 불변성: 생성 후 모든 attr frozen. 갱신은 새 인스턴스 생성.
    class Record
      include Sowing::Domain::Entry

      MODE = :record

      # 4축은 Capture::Item 와 동일 ENUM — DRY (단일 정의).
      SUBJECTS = Capture::Item::SUBJECTS

      attr_reader :id, :body, :tags, :title, :template, :category, :source,
        :promoted_from, :subject, :created_at, :updated_at

      def initialize(id:, body:, created_at:,
        title: nil, tags: Sowing::Domain::ValueObjects::TagSet.new,
        template: nil, updated_at: nil,
        category: nil, source: nil, promoted_from: nil, subject: nil)
        validate_ulid!(id, :id)
        validate_string!(body, :body)
        validate_tag_set!(tags)
        validate_time!(created_at, :created_at)
        validate_optional_string!(title, :title)
        validate_optional_string!(template, :template)
        validate_optional_string!(category, :category)
        validate_optional_string!(source, :source)
        validate_optional_string!(promoted_from, :promoted_from)
        validate_optional_subject!(subject)
        updated_at ||= created_at
        validate_time!(updated_at, :updated_at)

        @id = id
        @body = body.freeze
        @tags = tags
        @title = title&.freeze
        @template = template&.freeze
        @category = category&.freeze
        @source = source&.freeze
        @promoted_from = promoted_from&.freeze
        @subject = subject
        @created_at = created_at
        @updated_at = updated_at
        freeze
      end

      def mode
        MODE
      end

      def to_frontmatter
        common_frontmatter.merge(
          "category" => category,
          "source" => source, # nil 이면 .compact 로 제외 (Record-only 호환)
          "promoted_from" => promoted_from,
          "subject" => subject&.to_s
        ).compact
      end

      private

      def validate_optional_subject!(value)
        return if value.nil?
        return if SUBJECTS.include?(value)
        raise ArgumentError,
          "subject 는 #{SUBJECTS.inspect} 중 하나여야 합니다 (받은 값: #{value.inspect})"
      end
    end
  end
end
