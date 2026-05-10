# frozen_string_literal: true

require "front_matter_parser"

module Sowing
  module Controllers
    # 합성 결과 검토 UI — 통합 /synth 대시보드 (W17-T04 + W21-T04).
    #
    # vault/.sowing/synth/{type}/*.md 의 LLM/결정적 합성 산출물을 사용자가 검토 → 수락/거절.
    # 4 type 통합 (W21-T04, Phase 12 마지막 task):
    #   - students/        — Phase 11 학생 디제스트
    #   - reflections/     — Phase 12 학기 회고 (W21-T01)
    #   - patterns/        — Phase 12 수업 패턴 후보 (W21-T02)
    #   - contradictions/  — Phase 12 학생 묘사 변화 후보 (W21-T03)
    #
    # 수락: 정식 Record entry 로 변환 + 30_Records/{YYYY}/{category}/ 이동
    #   - synth_target 의 prefix 로 category 자동 매핑
    # 거절: 휴지통 (.sowing/trash) 이동
    #
    # 모든 결정은 audit log 에 기록 — Phase 11~12 의 사용자 선호 데이터 (preference dataset)
    # 로 활용 가능 (LLM 미세조정·프롬프트 개선).
    #
    # ADR-013 준수:
    #   - 자율 mutation 0 — 모든 변환은 사용자 명시 클릭 필요
    #   - 합성물은 별도 .sowing/synth/ 격리 — 사용자 글과 명확 구분
    #   - "LLM 합성" 배지 명시 — 의인화 카피 0
    class SynthController < ApplicationController
      include UseCases::Persistence

      # 4 합성 type — slug 검증 + URL 라우팅 + category 매핑 한 곳에서 관리.
      # `accept_category` 는 수락 시 정식 Record 의 category 로 매핑.
      SYNTH_TYPES = {
        "students" => {
          subdir: "students",
          label: "학생 디제스트",
          icon: "👤",
          accept_category: "학생기록",
          target_prefix: "student:"
        },
        "reflections" => {
          subdir: "reflections",
          label: "학기 회고",
          icon: "📅",
          accept_category: "학기회고",
          target_prefix: "semester:"
        },
        "patterns" => {
          subdir: "patterns",
          label: "수업 패턴 후보",
          icon: "🧩",
          accept_category: "수업기록",
          target_prefix: "patterns:"
        },
        "contradictions" => {
          subdir: "contradictions",
          label: "학생 묘사 변화",
          icon: "🔄",
          accept_category: "학생기록",
          target_prefix: "contradictions:"
        },
        "consultations" => {
          subdir: "consultations",
          label: "학부모 상담 준비",
          icon: "🤝",
          accept_category: "상담",
          target_prefix: "consultation:"
        }
      }.freeze

      RECENT_DAYS = 7  # "이번 주 새로 합성됨" 배지 기준

      helpers do
        def synth_root
          Infrastructure::Paths.vault_dir.join(".sowing/synth")
        end

        def synth_subdir(type)
          synth_root.join(SYNTH_TYPES.fetch(type)[:subdir])
        end

        def synth_vault_repo
          @synth_vault_repo ||= Repositories::VaultRepo.new(vault_dir: Infrastructure::Paths.vault_dir)
        end

        def synth_index_repo
          @synth_index_repo ||= Repositories::IndexRepo.new
        end

        def synth_audit_log
          Infrastructure::AuditLog.instance
        end

        def parse_synth_file(path)
          raw = File.read(path)
          parsed = FrontMatterParser::Parser.new(:md).call(raw)
          {
            path: Pathname.new(path),
            slug: File.basename(path, ".md"),
            fm: parsed.front_matter,
            body: parsed.content
          }
        end

        def list_synth(type)
          dir = synth_subdir(type)
          return [] unless dir.exist?
          Dir.glob(dir.join("*.md")).sort.map { |p| parse_synth_file(p) }
        end

        # 4 type 의 모든 파일을 한 번에 — 통합 dashboard 입구.
        def list_all_synth
          SYNTH_TYPES.keys.to_h { |type| [type, list_synth(type)] }
        end

        def synth_target_or_404(type, slug)
          halt_with_404("알 수 없는 합성 type: #{type}") unless SYNTH_TYPES.key?(type)
          target = synth_subdir(type).join("#{slug}.md")
          if target.exist?
            target
          else
            halt_with_404("합성 결과를 찾을 수 없습니다: #{type}/#{slug}")
          end
        end

        # synth_at 이 최근 RECENT_DAYS 이내면 "새로 합성됨" 배지.
        def recently_synthed?(synth)
          ts = synth[:fm]["synth_at"]
          return false if ts.nil?
          Time.parse(ts.to_s) >= (Time.now - RECENT_DAYS * 86_400)
        rescue
          false
        end

        def halt_with_404(message)
          status 404
          @page_title = "찾을 수 없음"
          @message = message
          halt erb(:"errors/404", layout: :"layouts/application")
        end

        # 통합 redirect — type-aware. 사용자 인풋 학생 이름·라벨이 한국어인 경우 escape 필수.
        def redirect_to_synth_show(type, slug)
          redirect "/synth/#{type}/#{Rack::Utils.escape(slug)}"
        end
      end

      # ─── 통합 대시보드 ───
      get "/synth" do
        @page_title = "합성 결과 검토"
        @all_synth = list_all_synth
        @synth_types = SYNTH_TYPES
        @flash = session.delete(:flash)
        erb :"synth/index", layout: :"layouts/application"
      end

      # ─── 상세 (4 type 통합) ───
      get "/synth/:type/:slug" do
        type = params["type"]
        slug = params["slug"]
        target = synth_target_or_404(type, slug)
        @type = type
        @type_meta = SYNTH_TYPES.fetch(type)
        @synth = parse_synth_file(target)
        @page_title = @synth[:fm]["title"] || @synth[:slug]
        @body_html = markdown_to_html(@synth[:body])
        @flash = session.delete(:flash)
        erb :"synth/show", layout: :"layouts/application"
      end

      # ─── 생성 (type-specific) ───

      # 학생 디제스트 — slug = 학생 이름
      post "/synth/students/:slug/generate" do
        student_name = params["slug"]
        result = UseCases::SynthesizeStudentDigest.new.call(student_name: student_name)
        if result.success?
          synth_audit_log.append(
            action: :synth_generate,
            entry_id: "synth:student:#{student_name}",
            mode: "record",
            path: ".sowing/synth/students/#{student_name}.md"
          )
          session[:flash] = "학생 디제스트 생성: #{student_name}"
          redirect_to_synth_show("students", student_name)
        else
          session[:flash] = "생성 실패 (#{result.failure}) — 학생 entity·mention 확인 필요"
          redirect "/synth"
        end
      end

      # 학기 회고 — semester_label 폼 입력 (since/until 옵션)
      post "/synth/reflections/generate" do
        label = params["semester_label"].to_s.strip
        if label.empty?
          session[:flash] = "학기 라벨이 필요합니다 (예: 2026-1)"
          redirect "/synth"
          next
        end
        result = UseCases::SynthesizeSemesterReflection.new.call(
          semester_label: label,
          since: params["since"].to_s.strip.empty? ? nil : params["since"],
          until_time: params["until_time"].to_s.strip.empty? ? nil : params["until_time"]
        )
        if result.success?
          synth_audit_log.append(
            action: :synth_generate,
            entry_id: "synth:semester:#{label}",
            mode: "record",
            path: ".sowing/synth/reflections/#{label}.md"
          )
          session[:flash] = "학기 회고 생성: #{label}"
          redirect_to_synth_show("reflections", label)
        else
          session[:flash] = "생성 실패 (#{result.failure}) — entries 수 확인 필요"
          redirect "/synth"
        end
      end

      # 수업 패턴 — 고정 slug "lessons"
      post "/synth/patterns/lessons/generate" do
        result = UseCases::ExtractLessonPatterns.new.call
        if result.success?
          synth_audit_log.append(
            action: :synth_generate,
            entry_id: "synth:patterns:lessons",
            mode: "record",
            path: ".sowing/synth/patterns/lessons.md"
          )
          session[:flash] = "수업 패턴 생성 완료"
          redirect_to_synth_show("patterns", "lessons")
        else
          session[:flash] = "생성 실패 (#{result.failure}) — 수업 카테고리 entries 확인"
          redirect "/synth"
        end
      end

      # 학부모 상담 준비 — slug = 학생 이름 (since/until 옵션)
      post "/synth/consultations/:slug/generate" do
        student_name = params["slug"]
        result = UseCases::SynthesizeParentConsultation.new.call(
          student_name: student_name,
          since: params["since"].to_s.strip.empty? ? nil : params["since"],
          until_time: params["until_time"].to_s.strip.empty? ? nil : params["until_time"]
        )
        if result.success?
          synth_audit_log.append(
            action: :synth_generate,
            entry_id: "synth:consultation:#{student_name}",
            mode: "record",
            path: ".sowing/synth/consultations/#{student_name}.md"
          )
          session[:flash] = "학부모 상담 준비 생성: #{student_name}"
          redirect_to_synth_show("consultations", student_name)
        else
          session[:flash] = "생성 실패 (#{result.failure}) — 학생 entity·상담 entries 확인"
          redirect "/synth"
        end
      end

      # 학생 변화 — 고정 slug "observations"
      post "/synth/contradictions/observations/generate" do
        result = UseCases::DetectContradictions.new.call
        if result.success?
          synth_audit_log.append(
            action: :synth_generate,
            entry_id: "synth:contradictions:observations",
            mode: "record",
            path: ".sowing/synth/contradictions/observations.md"
          )
          session[:flash] = "학생 변화 후보 생성 완료"
          redirect_to_synth_show("contradictions", "observations")
        else
          session[:flash] = "생성 실패 (#{result.failure}) — 학생 entity mention 확인"
          redirect "/synth"
        end
      end

      # ─── 수락 (4 type 통합) ───
      post "/synth/:type/:slug/accept" do
        type = params["type"]
        slug = params["slug"]
        target = synth_target_or_404(type, slug)
        synth = parse_synth_file(target)

        @vault_repo = synth_vault_repo
        @index_repo = synth_index_repo
        record = build_record_from_synth(synth, type)
        persist!(record)

        synth_audit_log.append(
          action: :synth_accept,
          entry_id: record.id.to_s,
          mode: "record",
          path: ".sowing/synth/#{SYNTH_TYPES.fetch(type)[:subdir]}/#{slug}.md"
        )

        File.unlink(target) if target.exist?
        cat = SYNTH_TYPES.fetch(type)[:accept_category]
        session[:flash] = "수락: 30_Records/{YYYY}/#{cat}/ 으로 이동했습니다."
        redirect "/synth"
      end

      # ─── 거절 (4 type 통합) ───
      post "/synth/:type/:slug/reject" do
        type = params["type"]
        slug = params["slug"]
        target = synth_target_or_404(type, slug)

        rel = target.relative_path_from(Infrastructure::Paths.vault_dir)
        synth_vault_repo.delete(rel)

        synth_audit_log.append(
          action: :synth_reject,
          entry_id: "synth:#{SYNTH_TYPES.fetch(type)[:target_prefix]}#{slug}",
          mode: "record",
          path: rel.to_s
        )
        session[:flash] = "거절: .sowing/trash 휴지통으로 이동했습니다."
        redirect "/synth"
      end

      private

      # synth_target 의 prefix 와 type 으로 적절한 Record 생성.
      def build_record_from_synth(synth, type)
        meta = SYNTH_TYPES.fetch(type)
        target_str = synth[:fm]["synth_target"].to_s
        target_value = target_str.sub(/^#{Regexp.escape(meta[:target_prefix])}/, "")
        title = synth[:fm]["title"] || "#{meta[:label]}: #{target_value}"

        Domain::Record.new(
          id: Domain::ValueObjects::Ulid.generate,
          title: title,
          body: synth[:body].to_s.strip,
          category: meta[:accept_category],
          created_at: Time.now,
          updated_at: Time.now,
          tags: Domain::ValueObjects::TagSet.new([])
        )
      end
    end
  end
end
