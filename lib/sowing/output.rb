# frozen_string_literal: true

module Sowing
  # Bounded Context #4 — Output (출력·전달, ADR-018).
  #
  # 책임: 비전 E.3 의 5 용도별 공식 양식 출력. 학교별·연도별 양식 차이는
  # 사용자 편집 가능 ERB template 으로 흡수.
  #
  # 출력 형식 3종:
  #   - Markdown (default, 옵시디언·iA Writer 등과 연계)
  #   - PDF (Prawn, 한글 Pretendard 폰트)
  #   - DOCX (caracal, ruby native)
  #
  # 5 Template (ADR-018, 게이트 #3 c — 5종 모두 MVP):
  #   - student_record (생기부)
  #   - consultation (상담부)
  #   - meeting_minutes (회의록)
  #   - project_proposal (사업계획서)
  #   - budget_request (예산요구서)
  #
  # 의존: Core + Capture + Knowledge + Insight (모두). 의존 그래프 의 top.
  module Output
    # Stage 4b (R4b) 부터 실제 구현. 현재는 stub.

    TEMPLATE_TYPES = %i[
      student_record consultation meeting_minutes
      project_proposal budget_request
    ].freeze

    FORMATS = %i[markdown pdf docx].freeze

    # @param type [Symbol] TEMPLATE_TYPES 중 하나
    # @param format [Symbol] FORMATS 중 하나
    # @param params [Hash] template-specific (예: student_name, date, slug)
    # @return [String, Pathname] 생성된 파일 경로 또는 본문
    def self.generate(type:, format: :markdown, **params)
      raise NotImplementedError, "Stage 4b R4b-T03~T07 에 구현"
    end
  end
end
