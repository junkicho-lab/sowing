# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 학생 1명의 단원평가 누적 추이 합성 (확장 합성기 #2).
    #
    # Phase 11/12 패턴 그대로 — 결정적 fallback + LLM 옵트인 + audit `with_actor("agent")` +
    # frontmatter `is_synth: true` + `.sowing/synth/` 격리.
    #
    # 입력 소스:
    #   1. records 의 `category ∈ DEFAULT_ASSESSMENT_CATEGORIES` (예: 평가/단원평가)
    #   2. 학생 entity mention entries 중 본문에 평가 키워드 (단원/평가/시험/수행/형성평가)
    #
    # 출력 구조 (학생당):
    #   - 단원별 평가 결과 (시간순)
    #   - 잘한 단원 / 보강이 필요한 단원 (긍정/부정 신호어 — Phase 12 LessonPattern 패턴 재사용)
    #   - 다음 학습 우선순위 제안 (LLM 모드)
    #
    # 자율 판단 0 (ADR-013):
    #   - 학생 능력 단정 X — 인용 + 단원명 + 날짜만
    #   - "민준이는 분수가 약하다" X / "분수 단원에서 '어려워했다' 라는 인용 1건" O
    #   - 평가 점수·등급 표현 자체는 LLM 가공 안 함 (사용자 본문 그대로 인용)
    #
    # 저장 위치: vault/.sowing/synth/assessments/{학생명}.md
    class SynthesizeAssessmentTrend
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/assessments"
      DEFAULT_WINDOW_DAYS = 180  # 6개월 (한 학기 분량)
      MIN_ENTRIES = 2
      MAX_ENTRIES = 200
      EXCERPT_LIMIT = 200

      DEFAULT_ASSESSMENT_CATEGORIES = %w[평가 단원평가].freeze
      ASSESSMENT_KEYWORDS = %w[단원 평가 시험 수행 형성평가 단원평가 수행평가].freeze

      # 강점/약점 분류 — Phase 12 LessonPattern 패턴 재사용 (부정 윈도 5자 필터).
      STRENGTH_KEYWORDS = %w[
        잘\ 풀 정확 또래\ 이상 평균\ 이상 빠르게\ 풀 잘\ 이해 우수 능숙
        효과적 깊이\ 이해 또박또박 자신감\ 있
      ].freeze

      WEAKNESS_KEYWORDS = %w[
        어려워 헤매 헷갈 못\ 따라 따라오지\ 못 부진 보강\ 필요 시간\ 부족
        실수 잘못\ 풀 더\ 연습 미흡 막혀
      ].freeze

      NEGATION_RE = /(?:안|못|없|지 못|하지 못)/

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
      # @param categories [Array<String>, nil] 평가 record 카테고리 override
      # @return [Result] Success(Pathname) | Failure(:entity_not_found | :no_entries | :too_many_entries)
      def call(student_name:, since: nil, until_time: nil, categories: nil)
        entity = @db[:entities].where(type: "student", name: student_name).first
        return Failure(:entity_not_found) if entity.nil?

        cats = (categories || DEFAULT_ASSESSMENT_CATEGORIES).map(&:to_s)
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        sources = collect_sources(entity, cats, since_t, until_t)
        return Failure(:no_entries) if sources.size < MIN_ENTRIES
        return Failure(:too_many_entries) if sources.size > MAX_ENTRIES

        analysis = classify_strength_weakness(sources, entity[:name])

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(student_name, sources, analysis, since_t, until_t)
          }
        else
          synthesize_deterministic(student_name, sources, analysis, since_t, until_t)
        end

        target = vault_target(student_name)
        content = build_full_content(student_name, body, sources, analysis, since_t, until_t, cats)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      # 평가 카테고리 records + 학생 mention 중 평가 키워드 entries 통합.
      def collect_sources(entity, cats, since_t, until_t)
        # (1) 평가 record 카테고리
        assessment_records = @db[:entries]
          .where(mode: "record", category: cats)
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .all

        # (2) 학생 mention entries
        mention_ids = @db[:entity_mentions].where(entity_id: entity[:id]).select_map(:entry_id)
        student_mentions = if mention_ids.any?
          @db[:entries]
            .where(id: mention_ids)
            .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
            .all
        else
          []
        end

        all_rows = (assessment_records + student_mentions).uniq { |r| r[:id] }

        student_name = entity[:name]
        all_rows.map { |row|
          body = read_body(row[:path])
          next nil if body.empty?

          # 학생 이름 + 평가 키워드 둘 다 만족해야 입력 가치 있음
          mentions_student = body.include?(student_name)
          mentions_assessment = ASSESSMENT_KEYWORDS.any? { |kw| body.include?(kw) }
          next nil unless mentions_student && mentions_assessment

          {
            id: row[:id],
            path: row[:path],
            mode: row[:mode],
            category: row[:category],
            created_at: row[:created_at],
            unit: extract_unit_label(body, student_name),
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

      # 단원 라벨 추출 — "분수 단원" / "곱셈 단원평가" 등 패턴.
      # 결정적 휴리스틱: 평가 키워드 직전 1~3 어절 = 단원명 추정.
      def extract_unit_label(body, _student_name)
        ASSESSMENT_KEYWORDS.each do |kw|
          idx = body.index(kw)
          next unless idx

          # 키워드 앞 30자 안에서 마지막 어절 추출
          prefix = body[[idx - 30, 0].max...idx].strip
          tokens = prefix.split(/[\s.,]/).reject(&:empty?)
          # 마지막 1~2 어절을 단원명으로
          unit = tokens.last(2).join(" ").strip
          return unit unless unit.empty?
        end
        "(단원 미상)"
      end

      def relevant_excerpt(body, student_name)
        sentences = body.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?)
        match = sentences.find { |s| s.include?(student_name) } || sentences.first || ""
        (match.length > EXCERPT_LIMIT) ? "#{match[0, EXCERPT_LIMIT]}…" : match
      end

      # 강점/약점 후보 분류 (부정 윈도 5자 필터 — Phase 12 LessonPattern 패턴).
      def classify_strength_weakness(sources, student_name)
        strengths = []
        weaknesses = []

        sources.each do |s|
          body = read_body(s[:path])
          next if body.empty?

          # 학생 이름 포함 문장만 분석
          body.split(/[.!?。\n]+/).each do |sent|
            sent = sent.strip
            next unless sent.include?(student_name)

            if matches_keywords_with_negation?(sent, STRENGTH_KEYWORDS)
              strengths << {unit: s[:unit], path: s[:path], date: s[:created_at].to_s[0, 10], sentence: clip(sent)}
            end
            if matches_keywords_with_negation?(sent, WEAKNESS_KEYWORDS)
              weaknesses << {unit: s[:unit], path: s[:path], date: s[:created_at].to_s[0, 10], sentence: clip(sent)}
            end
          end
        end

        {strengths: strengths, weaknesses: weaknesses}
      end

      def matches_keywords_with_negation?(sentence, keywords)
        keywords.any? do |kw|
          pattern = kw.gsub('\\ ', " ")
          idx = sentence.index(pattern)
          next false unless idx

          window_before = sentence[[idx - 5, 0].max...idx]
          window_after = sentence[(idx + pattern.length)...(idx + pattern.length + 5)]
          window = "#{window_before}#{window_after}"
          !window.match?(NEGATION_RE)
        end
      end

      def clip(text)
        cleaned = text.tr("\n", " ").strip
        (cleaned.length > EXCERPT_LIMIT) ? "#{cleaned[0, EXCERPT_LIMIT]}…" : cleaned
      end

      def synthesize_deterministic(_student_name, sources, analysis, _since_t, _until_t)
        lines = []
        lines << "## 📊 단원별 평가 결과 (#{sources.size}건, 시간순)"
        lines << ""

        sources.each_with_index do |s, i|
          lines << "### [#{i + 1}] #{s[:created_at].to_s[0, 10]} · #{s[:unit]}"
          lines << ""
          lines << "> #{s[:excerpt]}"
          lines << ""
          lines << "출처: [[#{s[:path]}]]"
          lines << ""
        end

        lines << "## 💪 잘한 단원 — 후보 인용 (#{analysis[:strengths].size}건)"
        lines << ""
        if analysis[:strengths].any?
          analysis[:strengths].each_with_index do |c, i|
            lines << "- **#{c[:unit]}** (#{c[:date]})"
            lines << "  > #{c[:sentence]}"
            lines << "  · [[#{c[:path]}]]"
            lines << ""
          end
        else
          lines << "_긍정 신호어 매칭 없음. LLM 모드에서 더 풍부한 추출 가능._"
          lines << ""
        end

        lines << "## 🌱 보강이 필요한 단원 — 후보 인용 (#{analysis[:weaknesses].size}건)"
        lines << ""
        if analysis[:weaknesses].any?
          analysis[:weaknesses].each_with_index do |c, i|
            lines << "- **#{c[:unit]}** (#{c[:date]})"
            lines << "  > #{c[:sentence]}"
            lines << "  · [[#{c[:path]}]]"
            lines << ""
          end
        else
          lines << "_부정 신호어 매칭 없음. LLM 모드에서 더 풍부한 추출 가능._"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (시간순 인용 + 문장 단위 키워드 분류, 부정 윈도 5자 필터)._"
        lines << "_학습 패턴·다음 우선순위 분석은 LLM 모드에서. 학생 능력 단정 X — 각 인용은 *후보* 일 뿐._"
        lines.join("\n")
      end

      def synthesize_via_llm(student_name, sources, analysis, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(student_name, sources, analysis, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(student_name, sources, analysis, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 학생의 평가 누적 추이를 정리합니다.
          입력은 시간순 단원평가 인용 + 1차 분류된 강점/약점 후보.
          톤: 객관적·관찰. "이 학생은 ~약하다" 단정 X. 본문에 없는 사실 만들기 금지.

          출력 마크다운 (모든 섹션 포함):
          ## 📊 단원별 평가 추이
          - 시간순 흐름 1~2 문장

          ## 💪 강점 단원 (관찰)
          - 단원명 + 인용 [#] (단정 X, "X 단원에서 '~' 라는 관찰 N건")

          ## 🌱 보강이 필요한 단원 (관찰)
          - 단원명 + 인용 [#] (단정 X)

          ## 📚 다음 학습 우선순위 (제안)
          - 본문 기반 구체 행동 1~3개. 부모님·학생에게 강요하는 톤 X

          분량: 400~1200자.
        TXT
      end

      def llm_user_prompt(student_name, sources, analysis, since_t, until_t)
        timeline = sources.map.with_index { |s, i|
          "[#{i + 1}] #{s[:created_at].to_s[0, 10]} · #{s[:unit]}: #{s[:excerpt]}"
        }.join("\n")
        strg = analysis[:strengths].map { |c| "- #{c[:unit]} (#{c[:date]}): #{c[:sentence]}" }.join("\n")
        weak = analysis[:weaknesses].map { |c| "- #{c[:unit]} (#{c[:date]}): #{c[:sentence]}" }.join("\n")
        <<~TXT
          # 학생: #{student_name}
          # 기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}

          # 시간순 평가 인용 (#{sources.size}건)
          #{timeline}

          # 결정적 분류 (1차)
          ## 강점 후보 (#{analysis[:strengths].size}건)
          #{strg.empty? ? "(없음)" : strg}

          ## 약점 후보 (#{analysis[:weaknesses].size}건)
          #{weak.empty? ? "(없음)" : weak}
        TXT
      end

      def build_full_content(student_name, body, sources, analysis, since_t, until_t, cats)
        units = sources.map { |s| s[:unit] }.uniq
        fm = {
          "is_synth" => true,
          "synth_target" => "assessment:#{student_name}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => sources.size,
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_categories" => cats,
          "synth_units" => units,
          "synth_strength_count" => analysis[:strengths].size,
          "synth_weakness_count" => analysis[:weaknesses].size,
          "synth_model" => synth_model_label,
          "title" => "평가 추이: #{student_name}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 평가 추이: #{student_name}\n\n#{body}\n"
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
