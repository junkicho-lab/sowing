# frozen_string_literal: true

module Sowing
  # Bounded Context #4 — Output (출력·전달, ADR-018).
  #
  # 책임: 비전 E.3 의 5 용도별 공식 양식 출력. 학교별·연도별 양식 차이는
  # 사용자 편집 가능 ERB template 으로 흡수 (게이트 #4 a).
  #
  # 출력 형식 3종:
  #   - Markdown (default, 옵시디언·iA Writer 등과 연계) — Stage 4b R4b MVP 완료
  #   - PDF (Prawn, 한글 Pretendard 폰트) — R4b-followup
  #   - DOCX (caracal, ruby native) — R4b-followup
  #
  # 5 Template (ADR-018, 게이트 #3 c — 5종 모두 MVP):
  #   - student_record (생기부)
  #   - consultation (상담부)
  #   - meeting_minutes (회의록)
  #   - project_proposal (사업계획서)
  #   - budget_request (예산요구서)
  #
  # 도메인:
  #   - Output::Template — 단일 ERB template (R4b-T01)
  #   - Output::TemplateRegistry — type → ERB 파일 lookup (R4b-T02)
  #
  # 의존: Core + Capture + Knowledge + Insight (모두). 의존 그래프 의 top.
  module Output
    TEMPLATE_TYPES = %i[
      student_record consultation meeting_minutes
      project_proposal budget_request
    ].freeze

    FORMATS = %i[markdown pdf docx].freeze

    @mutex = Mutex.new

    class << self
      # 단일 template 렌더 → 문자열 또는 파일 경로.
      # @param type [Symbol] TEMPLATE_TYPES 중 하나
      # @param format [Symbol] FORMATS 중 하나 (Stage 4b 는 :markdown 만 활성)
      # @param locals [Hash{Symbol=>Object}] template 변수 (ERB 안에서 메서드로 접근)
      # @param write_to [Pathname, String, nil] 지정 시 파일 저장 후 path 반환.
      #   nil 이면 렌더된 문자열 반환.
      # @return [String, Pathname]
      def generate(type:, format: :markdown, write_to: nil, **locals)
        validate_type!(type)
        validate_format!(format)

        case format.to_sym
        when :markdown
          rendered = render_markdown(type, locals)
          write_to ? write_file(write_to, rendered) : rendered
        when :pdf
          raise NotImplementedError,
            "PDF 출력은 Stage 4b followup 예정 (Prawn + 한글 Pretendard 폰트 통합)"
        when :docx
          raise NotImplementedError,
            "DOCX 출력은 Stage 4b followup 예정 (caracal gem)"
        end
      end

      # Registry — 외부에서 system_types 등 조회 가능.
      def registry
        @mutex.synchronize { @registry ||= TemplateRegistry.new }
      end

      attr_writer :registry

      def reset_registry!
        @mutex.synchronize { @registry = nil }
      end

      private

      def render_markdown(type, locals)
        template = registry.find(type: type, format: :markdown)
        template.render(locals)
      end

      def write_file(path, content)
        require "fileutils"
        abs = Pathname.new(path.to_s).expand_path
        FileUtils.mkdir_p(abs.dirname)
        File.write(abs, content, encoding: "UTF-8")
        abs
      end

      def validate_type!(type)
        return if TEMPLATE_TYPES.include?(type.to_sym)
        raise ArgumentError,
          "type 는 #{TEMPLATE_TYPES.inspect} 중 하나여야 합니다 (받은 값: #{type.inspect})"
      end

      def validate_format!(format)
        return if FORMATS.include?(format.to_sym)
        raise ArgumentError,
          "format 는 #{FORMATS.inspect} 중 하나여야 합니다 (받은 값: #{format.inspect})"
      end
    end
  end
end
