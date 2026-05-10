# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 수업 회고 누적에서 "잘된 / 아쉬웠던" 패턴 추출 (W21-T02).
    #
    # ADR-013 의 Phase 12 요건 (Phase 11~12 합성기 패턴 그대로 확장):
    #   - 결정적 fallback (문장 단위 키워드 분류 + top-N 인용, LLM 미사용 모드 1급)
    #   - LLM 옵트인 (의미 단위 패턴 추출은 LLM 모드에서만)
    #   - 결과는 *후보 패턴 + 인용 출처* — 사용자가 검토 후 정식 채택
    #     (자율 판단 0. "잘된 수업이다" 라고 단정하지 않고, 그렇게 묘사한 *문장 인용*
    #     만 모음)
    #   - audit log actor=agent 자동 마킹 (`with_actor` 블록)
    #
    # 결정적 모드 한계 인정:
    #   - 키워드 매칭은 false positive 발생 가능 ("잘 안 됐다" → "잘" 매칭).
    #     → 부정 표현(안/못/없/지 못/하지 못) 직후·앞 5자 안에 긍정 키워드 있으면 제외.
    #   - 진짜 패턴 추출은 LLM 모드에서. 결정적 모드는 *후보 문장 모음* 으로 honest.
    #
    # 저장 위치: vault/.sowing/synth/patterns/lessons.md
    #   - 단일 파일 — 패턴은 누적·재합성 (학생 디제스트가 학생당 1 파일인 것과 대비)
    #   - frontmatter `synth_target: "patterns:lessons"`
    class ExtractLessonPatterns
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/patterns"
      DEFAULT_LESSON_CATEGORIES = %w[수업 수업회고 lessons 도덕 도덕수업].freeze
      DEFAULT_WINDOW_DAYS = 180
      MIN_ENTRIES = 3      # 패턴 추출 최소 — 3건 이하면 패턴 아님
      MAX_ENTRIES = 500    # 안전 가드
      EXCERPT_LIMIT = 200
      TOP_PATTERN_N = 8    # 모드별 상위 N 후보 인용

      # 긍정 (잘된 수업) 신호어 — 한국 교사 회고 어휘.
      POSITIVE_KEYWORDS = %w[
        잘\ 됐 잘됐 잘\ 됨 잘됨 성공 좋았 활기 집중 흥미 흥미진진 참여 효과적
        만족 의미\ 있 의미있 보람 자발 적극 협력 몰입 감동
      ].freeze

      # 부정 (아쉬웠던 수업) 신호어.
      NEGATIVE_KEYWORDS = %w[
        어려웠 힘들 산만 부족 아쉬웠 아쉬움 실패 혼란 지루 소극적
        못\ 따라 따라오지\ 못 진행이\ 더디 시간이\ 부족 시간\ 부족
        효과\ 적었 의도와\ 다르 분위기가\ 무거 처지 처졌
      ].freeze

      # 부정 표현 후보 — 키워드 직후·앞 5자 안에 있으면 매칭 무효화.
      NEGATION_RE = /(?:안|못|없|지 못|하지 못|었지만|겠으나|는데도)/

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

      # @param categories [Array<String>, nil] 분석 대상 카테고리. nil 이면 기본 한국어 수업 카테고리
      # @param since [Time, String, nil] 시작 시점. nil 이면 6개월 전
      # @param until_time [Time, String, nil] 종료 시점. nil 이면 now
      # @return [Result] Success(Pathname) | Failure(:no_entries | :too_many_entries)
      def call(categories: nil, since: nil, until_time: nil)
        cats = (categories || DEFAULT_LESSON_CATEGORIES).map(&:to_s)
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        entry_rows = @db[:entries]
          .where(category: cats)
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .order(:created_at)
          .all
        return Failure(:no_entries) if entry_rows.size < MIN_ENTRIES
        return Failure(:too_many_entries) if entry_rows.size > MAX_ENTRIES

        # 본문 + 발췌 단위 인용 후보 수집 (결정적 — LLM 모드도 같은 입력 사용)
        candidates = collect_candidates(entry_rows)

        body = if @llm_backend
          Infrastructure::AuditLog.with_actor("agent") {
            synthesize_via_llm(candidates, cats, since_t, until_t)
          }
        else
          synthesize_deterministic(candidates, cats, since_t, until_t)
        end

        target = vault_target
        content = build_full_content(body, candidates, cats, since_t, until_t)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      # 각 entry 본문을 문장 단위로 쪼개 긍정/부정 신호 분류.
      # 구조: {success: [{path, sentence}], struggle: [{path, sentence}]}
      def collect_candidates(entry_rows)
        success_hits = []
        struggle_hits = []

        entry_rows.each do |row|
          body = read_body(row[:path])
          next if body.empty?

          sentences(body).each do |sent|
            next if sent.length < 5  # 너무 짧은 문장 노이즈 제거

            if matches_keywords?(sent, POSITIVE_KEYWORDS)
              success_hits << {path: row[:path], sentence: clip(sent), created_at: row[:created_at]}
            end
            if matches_keywords?(sent, NEGATIVE_KEYWORDS)
              struggle_hits << {path: row[:path], sentence: clip(sent), created_at: row[:created_at]}
            end
          end
        end

        {
          success: success_hits.first(TOP_PATTERN_N),
          struggle: struggle_hits.first(TOP_PATTERN_N),
          success_total: success_hits.size,
          struggle_total: struggle_hits.size
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

      # 한국어 문장 분리 — 종결부호(.!?。) 또는 줄바꿈.
      def sentences(text)
        text.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?)
      end

      def matches_keywords?(sentence, keywords)
        keywords.any? do |kw|
          # \s 가 keyword 안에 escape 된 경우 처리
          pattern = kw.gsub('\\ ', " ")
          idx = sentence.index(pattern)
          next false unless idx

          # 부정 표현이 키워드 앞 5자 / 뒤 5자 안에 있으면 매칭 무효화
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

      # 결정적: 후보 인용을 그대로 모아 표시. "패턴" 이라 단정 안 함 — 사용자가 패턴 발견.
      def synthesize_deterministic(candidates, _cats, _since_t, _until_t)
        lines = []

        lines << "## ✨ 잘된 수업 — 후보 인용 (#{candidates[:success].size}건)"
        lines << ""
        if candidates[:success].any?
          candidates[:success].each_with_index do |c, i|
            lines << "### [#{i + 1}] #{c[:created_at].to_s[0, 10]}"
            lines << ""
            lines << "> #{c[:sentence]}"
            lines << ""
            lines << "출처: [[#{c[:path]}]]"
            lines << ""
          end
        else
          lines << "_긍정 신호어 매칭 없음. LLM 모드에서 더 풍부한 추출 가능._"
          lines << ""
        end

        lines << "## 🌱 아쉬웠던 수업 — 후보 인용 (#{candidates[:struggle].size}건)"
        lines << ""
        if candidates[:struggle].any?
          candidates[:struggle].each_with_index do |c, i|
            lines << "### [#{i + 1}] #{c[:created_at].to_s[0, 10]}"
            lines << ""
            lines << "> #{c[:sentence]}"
            lines << ""
            lines << "출처: [[#{c[:path]}]]"
            lines << ""
          end
        else
          lines << "_부정 신호어 매칭 없음. LLM 모드에서 더 풍부한 추출 가능._"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (문장 단위 키워드 매칭, 부정 표현 5자 윈도 제외)._"
        lines << "_패턴 자체의 추출(공통점·메커니즘 분석)은 LLM 모드에서._"
        lines << "_각 인용은 후보일 뿐 — 사용자가 검토 후 *발견* 으로 받아들일 것._"
        lines.join("\n")
      end

      def synthesize_via_llm(candidates, cats, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(candidates, cats, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(candidates, cats, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 수업 회고에서 패턴을 추출합니다.
          입력은 긍정/부정 신호어로 1차 필터된 문장 인용 모음.
          톤: 따뜻하고 객관적. 단정 금지 — "패턴 후보" 로 표현.
          출처는 [[wikilink]] 보존. 본문에 없는 사실 만들기 금지.

          출력 마크다운 (모든 섹션 포함):
          ## ✨ 잘된 수업 — 공통점 후보
          - 각 후보 1~2 문장 + 인용 [#] 표기

          ## 🌱 아쉬웠던 수업 — 공통점 후보
          - 각 후보 1~2 문장 + 인용 [#] 표기

          ## 💡 다음 수업에 시도할 만한 것
          - 사용자가 직접 시도해볼 만한 구체적 행동 1~3개

          분량: 400~1200자.
        TXT
      end

      def llm_user_prompt(candidates, cats, since_t, until_t)
        succ = candidates[:success].map.with_index { |c, i|
          "[#{i + 1}] #{c[:created_at].to_s[0, 10]}: #{c[:sentence]}"
        }.join("\n")
        strg = candidates[:struggle].map.with_index { |c, i|
          "[#{i + 1}] #{c[:created_at].to_s[0, 10]}: #{c[:sentence]}"
        }.join("\n")
        <<~TXT
          # 카테고리: #{cats.join(", ")}
          # 기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}

          # ✨ 잘된 수업 후보 인용 (#{candidates[:success].size}건)
          #{succ.empty? ? "(없음)" : succ}

          # 🌱 아쉬웠던 수업 후보 인용 (#{candidates[:struggle].size}건)
          #{strg.empty? ? "(없음)" : strg}
        TXT
      end

      def build_full_content(body, candidates, cats, since_t, until_t)
        fm = {
          "is_synth" => true,
          "synth_target" => "patterns:lessons",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => candidates[:success_total] + candidates[:struggle_total],
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_categories" => cats,
          "synth_model" => synth_model_label,
          "title" => "수업 패턴 후보"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 수업 패턴 후보\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target
        @vault_dir.join(SYNTH_DIR, "lessons.md")
      end
    end
  end
end
