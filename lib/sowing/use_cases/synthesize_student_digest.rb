# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 학생당 1 디제스트 합성 — entity_mentions 의 인용 entries 를 모아 변화·패턴 정리 (W17-T02).
    #
    # ADR-013 의 Phase 11 요건:
    #   - 결정적 fallback (timeline + 인용 모음, LLM 미사용 모드 1급)
    #   - LLM 옵트인 (변화·패턴 분석은 LLM 모드에서만)
    #   - 합성 산출물은 반드시 frontmatter 표시 (is_synth: true) — 사용자 글과 명확히 구분
    #   - audit log actor=agent 자동 마킹 (with_actor 블록)
    #
    # 저장 위치: vault/.sowing/synth/students/{학생이름}.md
    #   - 마크다운 SoT (CLAUDE.md 1) — 옵시디언으로 직접 열람 가능
    #   - .sowing/ prefix 라 vault watcher 의 인덱싱 대상 아님 (자동 동기화 회피)
    #   - 사용자가 검토 후 수동으로 일반 entry 위치(20_Notes/30_Records)로 이동 가능
    #
    # 멱등: 같은 학생 재합성 → 기존 파일 atomic 덮어쓰기 (synth_at 갱신).
    class SynthesizeStudentDigest
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/students"
      DEFAULT_EXCERPT_LIMIT = 200

      def initialize(
        db: nil,
        vault_dir: nil,
        safe_writer: nil,
        llm_backend: nil,
        parser: nil,
        clock: Time
      )
        @db = db || Infrastructure::DB.connection
        @vault_dir = Pathname.new((vault_dir || Infrastructure::Paths.vault_dir).to_s).expand_path
        @safe_writer = safe_writer || Infrastructure::Filesystem::SafeWriter.new
        @llm_backend = llm_backend
        @parser = parser || FrontMatterParser::Parser.new(:md)
        @clock = clock
      end

      # @param student_name [String] entities.name (type=student)
      # @return [Result] Success(Pathname) | Failure(:entity_not_found | :no_mentions | :no_entries)
      def call(student_name:)
        entity = @db[:entities].where(type: "student", name: student_name).first
        return Failure(:entity_not_found) if entity.nil?

        entry_ids = @db[:entity_mentions].where(entity_id: entity[:id]).select_map(:entry_id).uniq
        return Failure(:no_mentions) if entry_ids.empty?

        entry_rows = @db[:entries].where(id: entry_ids).order(:created_at).all
        return Failure(:no_entries) if entry_rows.empty?

        citations = entry_rows.map { |row| build_citation(row, student_name) }

        digest_body = if @llm_backend
          Infrastructure::AuditLog.with_actor("agent") {
            synthesize_via_llm(student_name, citations)
          }
        else
          synthesize_deterministic(student_name, citations)
        end

        target = vault_target(student_name)
        content = build_full_content(student_name, digest_body, citations)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def build_citation(row, student_name)
        body = read_body(row[:path])
        {
          id: row[:id],
          path: row[:path],
          mode: row[:mode],
          created_at: row[:created_at],
          excerpt: relevant_excerpt(body, student_name)
        }
      end

      def read_body(rel_path)
        abs = @vault_dir.join(rel_path)
        return "" unless abs.exist?
        parsed = @parser.call(abs.read)
        parsed.content.to_s
      rescue
        ""
      end

      # 학생 이름이 등장한 첫 문장 발췌 — 인용의 핵심 맥락만.
      def relevant_excerpt(body, student_name)
        sentences = body.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?)
        match = sentences.find { |s| s.include?(student_name) }
        text = match || sentences.first || ""
        (text.length > DEFAULT_EXCERPT_LIMIT) ? "#{text[0, DEFAULT_EXCERPT_LIMIT]}…" : text
      end

      def synthesize_deterministic(student_name, citations)
        lines = []
        lines << "## 인용 entries (#{citations.size}건, 시간순)"
        lines << ""

        citations.each_with_index do |c, i|
          date = c[:created_at].to_s[0, 10]
          mode_icon = mode_icon(c[:mode])
          lines << "### [#{i + 1}] #{date} #{mode_icon} [[#{c[:path]}]]"
          lines << ""
          lines << "> #{c[:excerpt]}"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 디제스트는 결정적 합성 (timeline + 인용). 변화 패턴 분석은 LLM 모드에서._"
        lines.join("\n")
      end

      def mode_icon(mode)
        case mode.to_s
        when "memo" then "💭"
        when "note" then "📝"
        when "record" then "📖"
        else "·"
        end
      end

      def synthesize_via_llm(student_name, citations)
        response = @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(student_name, citations)
        )
        response.to_s.strip
      rescue
        # LLM 실패 시 결정적 폴백 — 사용자에게 빈 결과보다 나음.
        synthesize_deterministic(student_name, citations)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 학생 관찰 디제스트를 작성합니다.
          톤: 따뜻하고 객관적. 평가가 아닌 관찰. 추측·낙인 금지.
          출처 인용은 [#] 로 표기. 본문에 없는 사실 만들기 금지.

          출력 마크다운:
          ## 변화 요약 (시간 흐름)
          ## 주요 관찰
          ## 후속 과제 (관찰자가 시도할 만한 것)

          분량: 300~800 자.
        TXT
      end

      def llm_user_prompt(student_name, citations)
        cits = citations.map.with_index { |c, i|
          date = c[:created_at].to_s[0, 10]
          "[#{i + 1}] #{date}: #{c[:excerpt]}"
        }.join("\n")
        "# 학생: #{student_name}\n\n# 인용 entries (시간순)\n#{cits}\n"
      end

      def build_full_content(student_name, digest_body, citations)
        fm = {
          "is_synth" => true,
          "synth_target" => "student:#{student_name}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => citations.size,
          "synth_model" => synth_model_label,
          "title" => "학생 관찰: #{student_name}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 학생 관찰: #{student_name}\n\n#{digest_body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target(student_name)
        @vault_dir.join(SYNTH_DIR, "#{student_name}.md")
      end
    end
  end
end
