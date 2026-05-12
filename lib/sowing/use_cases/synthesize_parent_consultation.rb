# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 학부모 상담 준비 합성 — 학생 1명에 대해 학부모와 공유할 만한 관찰 모음 (확장 합성기 #1).
    #
    # Phase 11/12 패턴 그대로:
    #   - 결정적 fallback (상담 카테고리 entries + 학생 mention 통합 모음, LLM 0)
    #   - LLM 옵트인 (강점/변화/공유할 관찰/가정 제안 분석)
    #   - audit log actor=agent (with_actor 블록)
    #   - frontmatter `is_synth: true` + `synth_target: "consultation:{학생명}"`
    #
    # 입력 소스 (3 갈래 통합):
    #   1. records 의 category ∈ CONSULTATION_CATEGORIES (예: 상담/학부모상담)
    #   2. notes 의 category ∈ CONSULTATION_NOTE_CATEGORIES (예: meetings)
    #   3. 학생 entity mention entries 중 본문에 CONSULTATION_KEYWORDS 포함
    #
    # 사용자 시나리오:
    #   - 학기말 학부모 면담 1주 전, "민준 학부모 상담 준비 자료" 가 필요
    #   - 6개월 분량 entries 중 학부모와 공유할 만한 관찰을 자동 모음
    #   - 교사는 검토 후 수락 → 30_Records/{YYYY}/상담/ 으로 보존
    #
    # 자율 판단 0 (ADR-013):
    #   - "이 학생은 ~한 학생입니다" 단정 X
    #   - 인용 + 출처 + 날짜만 모음, 해석은 사용자
    #   - LLM 모드 도 "본문에 없는 사실 만들기 금지" prompt
    class SynthesizeParentConsultation
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/consultations"
      DEFAULT_WINDOW_DAYS = 180  # 6개월 (한 학기)
      MIN_ENTRIES = 2            # 최소 — 1건이면 합성 가치 없음
      MAX_ENTRIES = 200          # 안전 가드
      EXCERPT_LIMIT = 200

      DEFAULT_CONSULTATION_CATEGORIES = %w[상담 학부모상담].freeze
      DEFAULT_CONSULTATION_NOTE_CATEGORIES = %w[meetings].freeze
      DEFAULT_CONSULTATION_KEYWORDS = %w[학부모 면담 상담 부모님 가정].freeze

      def initialize(
        db: nil,
        vault_dir: nil,
        safe_writer: nil,
        llm_backend: nil,
        parser: nil,
        clock: Time
      )
        @db = db || Core::DB.connection
        @vault_dir = Pathname.new((vault_dir || Core::Paths.vault_dir).to_s).expand_path
        @safe_writer = safe_writer || Core::Filesystem::SafeWriter.new
        @llm_backend = llm_backend
        @parser = parser || FrontMatterParser::Parser.new(:md)
        @clock = clock
      end

      # @param student_name [String] entities.name (type=student)
      # @param since [Time, String, nil] 시작 시점. nil = 6개월 전
      # @param until_time [Time, String, nil] 종료 시점. nil = now
      # @param categories [Array<String>, nil] 상담 record 카테고리 override
      # @return [Result] Success(Pathname) | Failure(:entity_not_found | :no_entries | :too_many_entries)
      def call(student_name:, since: nil, until_time: nil, categories: nil)
        entity = @db[:entities].where(type: "student", name: student_name).first
        return Failure(:entity_not_found) if entity.nil?

        cats = (categories || DEFAULT_CONSULTATION_CATEGORIES).map(&:to_s)
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        sources = collect_sources(entity, cats, since_t, until_t)
        return Failure(:no_entries) if sources.size < MIN_ENTRIES
        return Failure(:too_many_entries) if sources.size > MAX_ENTRIES

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(student_name, sources, since_t, until_t)
          }
        else
          synthesize_deterministic(student_name, sources, since_t, until_t)
        end

        target = vault_target(student_name)
        content = build_full_content(student_name, body, sources, since_t, until_t, cats)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      # 3 갈래 입력 통합 → entry id UNIQUE → 시간순.
      def collect_sources(entity, cats, since_t, until_t)
        # (1) 상담 record 카테고리
        consult_records = @db[:entries]
          .where(mode: "record", category: cats)
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .all

        # (2) meetings note 카테고리
        meeting_notes = @db[:entries]
          .where(mode: "note", category: DEFAULT_CONSULTATION_NOTE_CATEGORIES)
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .all

        # (3) 학생 entity mention entries
        mention_ids = @db[:entity_mentions].where(entity_id: entity[:id]).select_map(:entry_id)
        student_mentions = if mention_ids.any?
          @db[:entries]
            .where(id: mention_ids)
            .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
            .all
        else
          []
        end

        all_rows = (consult_records + meeting_notes + student_mentions).uniq { |r| r[:id] }

        # 학생 이름 + 상담 키워드 필터링 (entry body 기반)
        student_name = entity[:name]
        all_rows.map { |row|
          body = read_body(row[:path])
          next nil if body.empty?

          # 본문이 학생 이름 OR 상담 키워드 둘 중 하나라도 포함해야 합성 가치 있음
          mentions_student = body.include?(student_name)
          mentions_consultation = DEFAULT_CONSULTATION_KEYWORDS.any? { |kw| body.include?(kw) }
          next nil unless mentions_student || mentions_consultation

          {
            id: row[:id],
            path: row[:path],
            mode: row[:mode],
            category: row[:category],
            created_at: row[:created_at],
            mentions_student: mentions_student,
            excerpt: relevant_excerpt(body, student_name)
          }
        }.compact.sort_by { |s| s[:created_at] }
      end

      def read_body(rel_path)
        abs = @vault_dir.join(rel_path)
        return "" unless abs.exist?
        parsed = @parser.call(abs.read)
        parsed.content.to_s
      rescue
        ""
      end

      # 학생 이름 포함 첫 문장 발췌 — 없으면 첫 문장.
      def relevant_excerpt(body, student_name)
        sentences = body.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?)
        match = sentences.find { |s| s.include?(student_name) } || sentences.first || ""
        (match.length > EXCERPT_LIMIT) ? "#{match[0, EXCERPT_LIMIT]}…" : match
      end

      def synthesize_deterministic(student_name, sources, _since_t, _until_t)
        lines = []
        lines << "## 📚 출처 entries (#{sources.size}건, 시간순)"
        lines << ""
        lines << "_학부모와 공유할 만한 관찰의 *원자료* 모음. 단정·해석은 교사 본인의 몫._"
        lines << ""

        sources.each_with_index do |s, i|
          icon = mode_icon(s[:mode])
          cat_label = s[:category].to_s.empty? ? "" : " · #{s[:category]}"
          lines << "### [#{i + 1}] #{s[:created_at].to_s[0, 10]} #{icon}#{cat_label}"
          lines << ""
          lines << "> #{s[:excerpt]}"
          lines << ""
          lines << "출처: [[#{s[:path]}]]"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (시간순 인용 모음). 강점·변화·가정 제안 분석은 LLM 모드에서._"
        lines << "_각 인용은 *원자료* — 실제 면담 자리에서는 교사의 직접 판단·맥락이 우선._"
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

      def synthesize_via_llm(student_name, sources, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(student_name, sources, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(student_name, sources, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 학부모 상담 준비 자료를 작성합니다.
          입력은 학생 mention + 상담 카테고리 entries 의 인용 모음.
          톤: 따뜻하고 객관적. 단정·낙인·사적 평가 금지. 본문에 없는 사실 만들기 금지.
          학부모와 공유 가능한 *관찰* 만 (사적 추측·심리 분석 금지).

          출력 마크다운 (모든 섹션 포함):
          ## 🌱 학생 강점 (관찰된 긍정적 모습)
          - 인용 [#] + 1문장 맥락

          ## 🔄 변화 / 성장 (시간순)
          - 인용 [#] + 변화 시점 표기

          ## 💬 학부모와 공유할 만한 관찰
          - 교사로서 학부모에게 전달하면 도움이 될 *사실* (해석 X)
          - 인용 [#] 필수

          ## 🤝 가정에서 함께 시도해 볼 만한 것 (제안)
          - 1~3 개. "~해보세요" 가 아닌 "~을 함께 해보면 어떨까요" 톤

          분량: 500~1500자.
        TXT
      end

      def llm_user_prompt(student_name, sources, since_t, until_t)
        list = sources.map.with_index { |s, i|
          icon = mode_icon(s[:mode])
          cat = s[:category].to_s.empty? ? "" : " · #{s[:category]}"
          "[#{i + 1}] #{s[:created_at].to_s[0, 10]} #{icon}#{cat}: #{s[:excerpt]}"
        }.join("\n")
        <<~TXT
          # 학생: #{student_name}
          # 기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}
          # 출처 entries (#{sources.size}건, 시간순)

          #{list}
        TXT
      end

      def build_full_content(student_name, body, sources, since_t, until_t, cats)
        fm = {
          "is_synth" => true,
          "synth_target" => "consultation:#{student_name}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => sources.size,
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_categories" => cats,
          "synth_model" => synth_model_label,
          "title" => "학부모 상담 준비: #{student_name}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 학부모 상담 준비: #{student_name}\n\n#{body}\n"
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
