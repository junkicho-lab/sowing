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

        # P16-T06 — 학생 이름에 해당하는 Insight 학생 디제스트가 이미 합성되어 있는지 조회.
        # 있으면 raw entries 보다 우선 사용 가능한 curated 결과.
        # @return [Sowing::Insight::Synthesis, nil]
        def find_existing_student_digest(student_name)
          return nil if student_name.to_s.strip.empty?
          Sowing::Insight.find("students:#{student_name.strip}")
        rescue
          nil # 인덱싱 실패 등 안전 폴백
        end

        # P16-T05 — 학생 이름으로 1년치 entries 자동 수집 → 학생부 textarea 채우기.
        #
        # 분류 휴리스틱 (자유 텍스트 카테고리 + 본문 키워드 기반):
        #   - 학습 활동: "수업", "발표", "학습", "공부", "성적", "과제" 키워드
        #   - 행동 특성: "친구", "교우", "관계", "성격", "태도", "리더", "갈등" 키워드
        #   - 둘 다 매칭이면 학습 우선 (생기부 학습 영역 우대)
        #   - 둘 다 미매칭이면 행동 특성 (기본값 — 일반 관찰)
        #
        # 반환: Hash { learning_activities: String, behavioral_observations: String, count: Integer }
        def auto_collect_student_entries(student_name, limit: 100)
          return {learning_activities: nil, behavioral_observations: nil, count: 0} if student_name.to_s.strip.empty?

          repo = Repositories::IndexRepo.new
          vault_repo_obj = Repositories::VaultRepo.new(vault_dir: Core::Paths.vault_dir)

          # search_with_filters 가 한글 비율 자동 라우팅 (FTS5 vs LIKE).
          results = repo.search_with_filters(q: student_name, limit: limit)
          # archived 자동 제외 — IndexRepo.list 와 일관 (R3-T05 ADR-017).
          results = results.reject(&:archived?)
          # plan 은 학생부 자료가 아님 — 회상 자료만.
          results = results.reject { |e| e.mode == :plan }

          learning = []
          behavioral = []

          results.sort_by(&:created_at).each do |indexed|
            entry = read_entry_safely(vault_repo_obj, indexed)
            next if entry.nil?
            next unless entry.body.include?(student_name) # name 이 body 에 실제 포함됨

            month = indexed.created_at.strftime("%-m월")
            excerpt = truncate_excerpt(entry.body, student_name, max: 140)
            bullet = "- (#{month}) #{excerpt}"

            if learning_keyword?(entry.body)
              learning << bullet
            else
              behavioral << bullet
            end
          end

          {
            learning_activities: learning.empty? ? nil : learning.uniq.join("\n"),
            behavioral_observations: behavioral.empty? ? nil : behavioral.uniq.join("\n"),
            count: learning.size + behavioral.size
          }
        end

        LEARNING_KEYWORDS = %w[수업 발표 학습 공부 성적 과제 단원 평가 토론 시험].freeze
        BEHAVIORAL_KEYWORDS = %w[친구 교우 관계 성격 태도 리더 갈등 협력 정리 책임].freeze

        def learning_keyword?(text)
          LEARNING_KEYWORDS.any? { |k| text.include?(k) }
        end

        # 학생 이름 주변 문맥을 발췌 — name 포함 문장 또는 짧은 라인.
        def truncate_excerpt(body, student_name, max: 140)
          body.each_line do |line|
            next unless line.include?(student_name)
            stripped = line.strip
            return stripped.length > max ? "#{stripped[0, max]}…" : stripped
          end
          # 줄 단위로 못 찾으면 body 의 앞부분 (이상 케이스 안전망)
          body.strip[0, max]
        end

        def read_entry_safely(vault_repo, indexed)
          vault_repo.read(indexed.path)
        rescue Errno::ENOENT, ArgumentError
          nil
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
        @auto_summary = nil

        # P16-T05 — 학생부 자동 채우기: ?student=NAME 가 있으면 entries 자동 수집
        if type == "student_record" && params["student"].to_s.strip != ""
          student_name = params["student"].to_s.strip
          @form["student_name"] = student_name
          @form["date"] = Date.today.iso8601
          @form["academic_year"] = Time.now.year.to_s

          # P16-T06 — Insight 합성 결과 (학생 디제스트) 가 있으면 별도 표시.
          # use_synth=1 일 때 합성 결과를 우선 사용 (raw entries 대신).
          @existing_digest = find_existing_student_digest(student_name)
          use_synth = params["use_synth"].to_s == "1" && @existing_digest

          if use_synth
            # 합성 결과의 body 를 learning_activities 에 통째로 — 사용자가 split 가능
            @form["learning_activities"] = @existing_digest.body
            @form["behavioral_observations"] = nil
            @auto_summary = {
              student: student_name,
              count: 1,
              source: :digest,
              digest_synth_at: @existing_digest.synth_at,
              digest_source_count: @existing_digest.source_count
            }
          else
            auto = auto_collect_student_entries(student_name)
            @form["learning_activities"] = auto[:learning_activities]
            @form["behavioral_observations"] = auto[:behavioral_observations]
            @auto_summary = {
              student: student_name,
              count: auto[:count],
              source: :entries,
              learning_count: auto[:learning_activities]&.lines&.count || 0,
              behavioral_count: auto[:behavioral_observations]&.lines&.count || 0
            }
          end
        end

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
