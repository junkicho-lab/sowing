# frozen_string_literal: true

module Sowing
  module Controllers
    # Phase 16 P16-T04 — 공식 양식 생성 페이지 (생기부·상담부·회의록 등).
    #
    # 비전 E.3 "출력" 단계 — 1년 동안 모은 raw 기록을 학교가 원하는 공식 양식으로
    # 한 번에 변환. 5 ERB template (templates/exports/) 을 form 으로 노출하고
    # 사용자 입력 → Sowing::Output.generate → 마크다운·PDF·DOCX 다운로드.
    #
    # 라우트:
    #   GET  /generate                     — 5 template 카드 landing
    #   GET  /generate/:template           — 해당 template 의 form
    #   POST /generate/:template           — form 제출 → render → download
    class GenerateController < ApplicationController
      TEMPLATE_META = {
        "student_record" => {
          label: "생기부 (생활기록부)",
          icon: "🎓",
          description: "학생 1명의 학기/학년 학습 활동·행동 특성 종합 의견"
        },
        "consultation" => {
          label: "상담부",
          icon: "🤝",
          description: "학부모·학생·진로 상담 기록 (공식 보관용)"
        },
        "meeting_minutes" => {
          label: "회의록",
          icon: "📋",
          description: "교과·학년·전체 회의 의사록 (안건·논의·결정사항)"
        },
        "project_proposal" => {
          label: "사업계획서",
          icon: "📑",
          description: "교육 사업·프로그램 기획 (목적·추진·예산·평가)"
        },
        "budget_request" => {
          label: "예산요구서",
          icon: "💰",
          description: "교과·학년 예산 신청 (항목별 산출 + 집행 계획)"
        }
      }.freeze

      helpers do
        def template_meta(type)
          TEMPLATE_META.fetch(type.to_s, nil)
        end

        def generate_format_for(params_format)
          allowed = %i[markdown pdf docx]
          fmt = params_format&.to_sym || :markdown
          allowed.include?(fmt) ? fmt : :markdown
        end

        # form 의 multi-value 입력 (예: agenda[]) → Array. 공백·빈 줄 자동 제거.
        def array_param(raw)
          return [] if raw.nil?
          Array(raw).map { |v| v.to_s.strip }.reject(&:empty?)
        end
      end

      get "/generate" do
        @page_title = "공식 양식 생성"
        @templates = TEMPLATE_META
        erb :"generate/index", layout: :"layouts/application"
      end

      get "/generate/:template" do
        type = params["template"]
        @meta = template_meta(type)
        halt 404, "지원하지 않는 template: #{type}" if @meta.nil?

        @template_type = type.to_sym
        @page_title = "#{@meta[:label]} 작성"
        @form = {}
        @error = nil

        view_name = :"generate/#{type}"
        erb view_name, layout: :"layouts/application"
      end

      post "/generate/:template" do
        type = params["template"]
        meta = template_meta(type)
        halt 404, "지원하지 않는 template: #{type}" if meta.nil?

        format = generate_format_for(params["format"])
        locals = build_locals_for(type, params)

        begin
          output = Sowing::Output.generate(type: type.to_sym, format: format, **locals)
          send_export(meta[:label], format, output)
        rescue ArgumentError => e
          @template_type = type.to_sym
          @meta = meta
          @form = params.dup
          @error = e.message
          @page_title = "#{meta[:label]} 작성"
          status 422
          erb :"generate/#{type}", layout: :"layouts/application"
        end
      end

      private

      # 각 template 별 form param → locals Hash. nil/empty 키는 ERB 에서 || 폴백.
      def build_locals_for(type, params)
        case type.to_s
        when "student_record"
          {
            student_name: params["student_name"],
            grade: params["grade"],
            grade_class: params["grade_class"],
            date: params["date"],
            teacher_name: params["teacher_name"],
            academic_year: params["academic_year"],
            learning_activities: params["learning_activities"],
            behavioral_observations: params["behavioral_observations"]
          }
        when "consultation"
          {
            consultation_date: params["consultation_date"],
            consultation_time: params["consultation_time"],
            consultee: params["consultee"],
            student_name: params["student_name"],
            relationship: params["relationship"],
            consultation_method: params["consultation_method"],
            topic: params["topic"],
            teacher_name: params["teacher_name"],
            consultation_content: params["consultation_content"],
            follow_up: params["follow_up"]
          }
        when "meeting_minutes"
          {
            meeting_title: params["meeting_title"],
            meeting_date: params["meeting_date"],
            meeting_time: params["meeting_time"],
            location: params["location"],
            attendees: array_param(params["attendees"]&.split(/[,\n]/)),
            absent_members: array_param(params["absent_members"]&.split(/[,\n]/)),
            recorder: params["recorder"],
            teacher_name: params["teacher_name"],
            agenda: array_param(params["agenda"]&.split("\n")),
            discussion: params["discussion"],
            decisions: array_param(params["decisions"]&.split("\n")),
            next_meeting: params["next_meeting"]
          }
        when "project_proposal"
          {
            project_title: params["project_title"],
            submission_date: params["submission_date"],
            proposer: params["proposer"],
            teacher_name: params["teacher_name"],
            department: params["department"],
            project_period: params["project_period"],
            budget_total: params["budget_total"],
            project_summary: params["project_summary"],
            objectives: params["objectives"],
            implementation_plan: params["implementation_plan"],
            milestones: array_param(params["milestones"]&.split("\n")),
            budget_breakdown: params["budget_breakdown"],
            evaluation_plan: params["evaluation_plan"]
          }
        when "budget_request"
          {
            request_title: params["request_title"],
            request_date: params["request_date"],
            requester: params["requester"],
            teacher_name: params["teacher_name"],
            department: params["department"],
            fiscal_year: params["fiscal_year"],
            total_amount: params["total_amount"],
            rationale: params["rationale"],
            line_items: parse_line_items(params),
            execution_plan: params["execution_plan"]
          }
        else {}
        end
      end

      # budget_request 의 line_items[idx][name] 동적 입력 → Array[Hash] 변환.
      # Sinatra/Rack 은 line_items 를 Hash{"0" => Hash, "1" => Hash, ...} 로 파싱.
      # Array 형태 (line_items[][name]) 도 안전하게 처리.
      def parse_line_items(params)
        raw = params["line_items"]
        items = case raw
        when Hash then raw.values
        when Array then raw
        else return []
        end

        items.filter_map { |item|
          next nil unless item.is_a?(Hash)
          h = {
            name: item["name"],
            unit_price: item["unit_price"],
            quantity: item["quantity"],
            amount: item["amount"],
            note: item["note"]
          }
          # 모든 필드가 빈 행은 제외
          h if h.values.any? { |v| !v.to_s.strip.empty? }
        }
      end

      def send_export(label, format, output)
        case format
        when :markdown
          content_type "text/markdown; charset=utf-8"
          attach_filename(label, "md")
          output
        when :pdf
          content_type "application/pdf"
          attach_filename(label, "pdf")
          output
        when :docx
          content_type "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
          attach_filename(label, "docx")
          output
        end
      end
    end
  end
end
