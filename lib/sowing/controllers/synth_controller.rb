# frozen_string_literal: true

require "front_matter_parser"

module Sowing
  module Controllers
    # 합성 결과 검토 UI (W17-T04).
    #
    # vault/.sowing/synth/students/*.md 의 LLM 합성 디제스트를 사용자가 검토 → 수락/거절.
    # 수락: 정식 Record entry 로 변환 + 30_Records/{YYYY}/학생기록/ 이동 (Persistence#persist!)
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

      helpers do
        def synth_dir
          Infrastructure::Paths.vault_dir.join(".sowing/synth/students")
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

        def list_synth_students
          return [] unless synth_dir.exist?
          Dir.glob(synth_dir.join("*.md")).sort.map { |p| parse_synth_file(p) }
        end

        def synth_target_or_404(slug)
          target = synth_dir.join("#{slug}.md")
          if target.exist?
            target
          else
            halt_with_404("합성 결과를 찾을 수 없습니다: #{slug}")
          end
        end

        def halt_with_404(message)
          status 404
          @page_title = "찾을 수 없음"
          @message = message
          halt erb(:"errors/404", layout: :"layouts/application")
        end
      end

      get "/synth" do
        @page_title = "합성 결과 검토"
        @students = list_synth_students
        @flash = session.delete(:flash)
        erb :"synth/index", layout: :"layouts/application"
      end

      get "/synth/students/:slug" do
        target = synth_target_or_404(params["slug"])
        @synth = parse_synth_file(target)
        @page_title = @synth[:fm]["title"] || @synth[:slug]
        @body_html = markdown_to_html(@synth[:body])
        @flash = session.delete(:flash)
        erb :"synth/show", layout: :"layouts/application"
      end

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
          session[:flash] = "디제스트 생성 완료: #{student_name}"
          redirect "/synth/students/#{Rack::Utils.escape(student_name)}"
        else
          session[:flash] = "생성 실패 (#{result.failure}) — 학생 entity·mention 확인 필요"
          redirect "/synth"
        end
      end

      post "/synth/students/:slug/accept" do
        slug = params["slug"]
        target = synth_target_or_404(slug)
        synth = parse_synth_file(target)

        # 정식 Record entry 로 변환 + persist (audit :create 가 자동 기록됨)
        @vault_repo = synth_vault_repo
        @index_repo = synth_index_repo
        record = build_record_from_synth(synth)
        persist!(record)

        # synth-specific audit (Phase 11~12 preference 데이터)
        synth_audit_log.append(
          action: :synth_accept,
          entry_id: record.id.to_s,
          mode: "record",
          path: ".sowing/synth/students/#{slug}.md"
        )

        # 원본 synth 파일 제거 (수락 후 검토 대상 아님). 휴지통 안 거침 — 새 record 가 보존된 형태.
        File.unlink(target) if target.exist?
        session[:flash] = "수락: 30_Records/{YYYY}/학생기록/ 으로 이동했습니다."
        redirect "/synth"
      end

      post "/synth/students/:slug/reject" do
        slug = params["slug"]
        target = synth_target_or_404(slug)

        # vault 기준 상대경로로 휴지통 이동
        rel = target.relative_path_from(Infrastructure::Paths.vault_dir)
        synth_vault_repo.delete(rel)

        synth_audit_log.append(
          action: :synth_reject,
          entry_id: "synth:student:#{slug}",
          mode: "record",
          path: rel.to_s
        )
        session[:flash] = "거절: .sowing/trash 휴지통으로 이동했습니다."
        redirect "/synth"
      end

      private

      def build_record_from_synth(synth)
        target_str = synth[:fm]["synth_target"].to_s
        student_name = target_str.sub(/^student:/, "")
        title = synth[:fm]["title"] || "학생 관찰: #{student_name}"

        Domain::Record.new(
          id: Domain::ValueObjects::Ulid.generate,
          title: title,
          body: synth[:body].to_s.strip,
          category: "학생기록",
          created_at: Time.now,
          updated_at: Time.now,
          tags: Domain::ValueObjects::TagSet.new([])
        )
      end
    end
  end
end
