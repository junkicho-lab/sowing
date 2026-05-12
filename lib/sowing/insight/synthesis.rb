# frozen_string_literal: true

module Sowing
  module Insight
    # Insight::Synthesis — 합성 결과 1건 (Phase R Stage 4a R4a-T01).
    #
    # 18 type 의 합성기 (17 + self-mirror) 가 생성하는 파일 단위 artifact.
    # 옵시디언 매핑: .sowing/synth/{type}/{slug}.md
    #
    # Entry (Memo/Record/Plan) 와 다른 점:
    #   - mode 가 :memo/:record/:plan 이 아님 — entries 테이블에 인덱싱 안 됨
    #   - id 는 ULID 가 아니라 "{type}:{slug}" (path 기반 synthetic)
    #   - status 는 :pending 만 — 수락 시 Knowledge::Record 로 이전 (파일 사라짐),
    #     거절 시 휴지통 (파일 사라짐). 즉 Synthesis 객체 자체는 항상 pending.
    #
    # 의존: Core (Filesystem 만). Knowledge·Capture 무관 — 자체 폴더에 독립 존재.
    #
    # 불변성: 생성 후 모든 attr frozen.
    class Synthesis
      # ADR-013 — Synthesis 의 유일한 상태. accept/reject 는 객체 외부 (파일 이동).
      STATUS = :pending

      attr_reader :type, :target, :title, :body, :synth_at, :source_count,
        :model, :extras, :path

      # @param type [Symbol] SYNTHESIZER_TYPES (예: :students, :"self-mirror") 중 하나
      # @param target [String] synth_target frontmatter 값 (예: "student:김철수")
      # @param title [String]
      # @param body [String]
      # @param synth_at [Time]
      # @param source_count [Integer] 합성에 사용된 entry 수
      # @param model [String, nil] LLM 모델 이름 또는 "deterministic"
      # @param extras [Hash] type-specific frontmatter (synth_period 등)
      # @param path [Pathname, String] 파일 위치 (vault-기준 상대 또는 절대)
      def initialize(type:, target:, title:, body:, synth_at:,
        source_count: 0, model: nil, extras: {}, path: nil)
        validate_type!(type)
        validate_string!(target, :target)
        validate_string!(title, :title)
        validate_string!(body, :body)
        validate_time!(synth_at, :synth_at)

        @type = type.to_sym
        @target = target.freeze
        @title = title.freeze
        @body = body.freeze
        @synth_at = synth_at
        @source_count = source_count.to_i
        @model = model&.to_s&.freeze
        @extras = extras.dup.freeze
        @path = path ? Pathname.new(path.to_s).freeze : nil
        freeze
      end

      # 합성 시점이 최근 N 일 이내인지 — UI "새로 합성됨" 배지 (현재 7일).
      def recent?(now: Time.now, days: 7)
        synth_at > now - days * 86_400
      end

      def id
        "#{type}:#{target_slug}"
      end

      def status
        STATUS
      end

      # frontmatter 4 표준 키 + extras + 본문 → 옵시디언 호환 마크다운.
      def to_markdown
        require "yaml"
        fm = {
          "is_synth" => true,
          "synth_target" => target,
          "synth_at" => synth_at.iso8601,
          "synth_source_count" => source_count
        }
        fm["synth_model"] = model if model
        fm["title"] = title
        fm.merge!(extras.transform_keys(&:to_s))
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        body_text = body.sub(/\n+\z/, "")
        "---\n#{yaml_body}---\n\n# #{title}\n\n#{body_text}\n"
      end

      private

      # target ("student:김철수") → slug ("김철수") for id 안정성.
      def target_slug
        target.split(":", 2).last.to_s
      end

      def validate_type!(value)
        return if SYNTHESIZER_TYPES.include?(value.to_s)
        raise ArgumentError,
          "type 는 SYNTHESIZER_TYPES 중 하나여야 합니다 (받은 값: #{value.inspect})"
      end

      def validate_string!(value, name)
        return if value.is_a?(String)
        raise ArgumentError, "#{name} 은 String 이어야 합니다 (받은 타입: #{value.class})"
      end

      def validate_time!(value, name)
        return if value.is_a?(Time)
        raise ArgumentError, "#{name} 은 Time 이어야 합니다 (받은 타입: #{value.class})"
      end
    end
  end
end
