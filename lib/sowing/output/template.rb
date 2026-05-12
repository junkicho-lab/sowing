# frozen_string_literal: true

require "erb"

module Sowing
  module Output
    # Output::Template — 단일 ERB template (Phase R Stage 4b R4b-T01).
    #
    # 한 type 의 한 format 을 표현. 학교별 양식 차이는 사용자가 vault 의 override
    # ERB 파일을 만들어 흡수 (ADR-018, 게이트 #4 a).
    #
    # 의존: Core 만 — stdlib ERB 사용 (외부 gem 없음).
    class Template
      attr_reader :type, :format, :source_path, :erb_source

      # @param type [Symbol] TEMPLATE_TYPES 중 하나 (:student_record 등)
      # @param format [Symbol] FORMATS 중 하나 (:markdown — Stage 4b MVP)
      # @param source_path [Pathname] ERB 파일 경로
      # @param erb_source [String] ERB 원본 소스 (캐시용)
      def initialize(type:, format:, source_path:, erb_source:)
        validate_type!(type)
        validate_format!(format)

        @type = type.to_sym
        @format = format.to_sym
        @source_path = Pathname.new(source_path.to_s).freeze
        @erb_source = erb_source.freeze
        freeze
      end

      # ERB 렌더링 — locals Hash 를 ERB binding 으로 노출.
      # trim_mode "-" 로 <% -%> 줄바꿈 제거 지원.
      # @param locals [Hash{Symbol=>Object}]
      # @return [String] 렌더된 문자열 (format=markdown 이면 마크다운 본문)
      def render(locals = {})
        unless locals.is_a?(Hash)
          raise ArgumentError, "locals 는 Hash 이어야 합니다 (받은 타입: #{locals.class})"
        end

        # ERB binding — locals 키를 메서드처럼 호출 가능하게.
        # Object 새 인스턴스의 singleton class 에 정의해 안전 격리.
        env = LocalsBinding.new(locals)
        ERB.new(erb_source, trim_mode: "-").result(env.instance_eval { binding })
      end

      private

      # ERB 내부에서 `<%= student_name %>` 형태로 locals 접근.
      # 누락된 키는 NoMethodError 가 아닌 nil 반환 (ERB 표현식이 깨지지 않게).
      class LocalsBinding
        def initialize(locals)
          @locals = locals
        end

        # method_missing 로 locals[key] 흉내 — 키 없으면 nil.
        # ?, ! 메서드 호출은 별도 처리 (ERB 내부 boolean check 대비).
        def method_missing(name, *args)
          return @locals.fetch(name, nil) if args.empty?
          super
        end

        def respond_to_missing?(_name, _include_private = false)
          true
        end
      end

      def validate_type!(value)
        return if TEMPLATE_TYPES.include?(value.to_sym)
        raise ArgumentError,
          "type 는 #{TEMPLATE_TYPES.inspect} 중 하나여야 합니다 (받은 값: #{value.inspect})"
      end

      def validate_format!(value)
        return if FORMATS.include?(value.to_sym)
        raise ArgumentError,
          "format 는 #{FORMATS.inspect} 중 하나여야 합니다 (받은 값: #{value.inspect})"
      end
    end
  end
end
