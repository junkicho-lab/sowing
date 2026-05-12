# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 학부모 상담 누적 패턴 — 학급 전체의 학기 상담 분석 (확장 합성기 #9).
    #
    # vs #1 SynthesizeParentConsultation:
    #   - #1: 학생 1명 + 면담 *준비* 자료
    #   - #9: 학급 전체 + 학기 상담 *패턴* 분석 — 학생별 빈도 / 공통 주제 / 다음
    #         학기 우선 면담 학생 제안
    #
    # 입력:
    #   - records 의 category ∈ DEFAULT_CONSULTATION_CATEGORIES (상담/학부모상담)
    #   - notes 의 category ∈ DEFAULT_CONSULTATION_NOTE_CATEGORIES (meetings)
    #   - 학기 window (default 6개월)
    #
    # 출력:
    #   - 결정적: 학생별 상담 빈도 + 공통 키워드 빈도 + 학기 timeline + 미상담 학생
    #     (class_roster 와 비교)
    #   - LLM: 학급 상담 흐름 / 가족 환경 패턴 / 학습 환경 패턴 / 다음 학기 우선
    #          면담 학생 제안 (단정 금지, 인용 기반)
    #
    # 자율 판단 0 (ADR-013):
    #   - "이 학급은 ~ 하다" 단정 X — 인용 + 통계만
    #   - 학부모 정보 가공 X — 본문에 명시된 사실만
    #   - 우선 면담 제안도 *후보* 로 제시, 강요 X
    #
    # 저장 위치: vault/.sowing/synth/parent-patterns/{semester_label}.md
    class SynthesizeParentPatterns
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/parent-patterns"
      DEFAULT_WINDOW_DAYS = 180  # 6개월 (한 학기)
      MIN_ENTRIES = 2
      MAX_ENTRIES = 300
      EXCERPT_LIMIT = 200
      TOP_KEYWORD_N = 12

      DEFAULT_CONSULTATION_CATEGORIES = %w[상담 학부모상담].freeze
      DEFAULT_CONSULTATION_NOTE_CATEGORIES = %w[meetings].freeze

      # 상담 도메인 한국어 명사 (빈도 분석 시 noise 제거).
      # SynthesizeParentConsultation 의 keywords 와 다름 — 여기선 *주제 단어* 추출이 목적.
      STOPWORDS = %w[
        오늘 내일 어제 학생 학생들 우리 모두 시간 활동 정리 진행 이번 다음
        학부모 면담 상담 부모님 이야기 어머니 아버지 가정 이번주 이번달
        있다 없다 하다 되다 이다 그러다 그렇다 좋다 어렵다
      ].freeze
      KOREAN_PARTICLES = %w[은 는 이 가 을 를 의 와 과 에 도 만 으로 로 부터 까지 에서 께 께서].freeze

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

      # @param semester_label [String] 학기 라벨 (예: "2026-1")
      # @param since [Time, String, nil] 시작 시점 (default 6개월 전)
      # @param until_time [Time, String, nil] 종료 시점 (default now)
      # @param categories [Array<String>, nil] 상담 record 카테고리 override
      # @return [Result] Success(Pathname) | Failure(:no_entries | :too_many_entries)
      def call(semester_label:, since: nil, until_time: nil, categories: nil)
        cats = (categories || DEFAULT_CONSULTATION_CATEGORIES).map(&:to_s)
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        sources = collect_sources(cats, since_t, until_t)
        return Failure(:no_entries) if sources.size < MIN_ENTRIES
        return Failure(:too_many_entries) if sources.size > MAX_ENTRIES

        analysis = analyze(sources)

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(semester_label, sources, analysis, since_t, until_t)
          }
        else
          synthesize_deterministic(semester_label, sources, analysis, since_t, until_t)
        end

        target = vault_target(semester_label)
        content = build_full_content(semester_label, body, sources, analysis, since_t, until_t, cats)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      # 두 갈래 통합 (records 상담 카테고리 + meetings notes), entry id UNIQUE, 시간순.
      def collect_sources(cats, since_t, until_t)
        records = @db[:entries]
          .where(mode: "record", category: cats)
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .all

        notes = @db[:entries]
          .where(mode: "note", category: DEFAULT_CONSULTATION_NOTE_CATEGORIES)
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .all

        all_rows = (records + notes).uniq { |r| r[:id] }

        all_rows.map { |row|
          body = read_body(row[:path])
          next nil if body.empty?

          {
            id: row[:id],
            path: row[:path],
            mode: row[:mode],
            category: row[:category],
            created_at: row[:created_at],
            body: body,
            excerpt: clip(body.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?).first.to_s)
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

      def clip(text)
        cleaned = text.tr("\n", " ").strip
        (cleaned.length > EXCERPT_LIMIT) ? "#{cleaned[0, EXCERPT_LIMIT]}…" : cleaned
      end

      # 학생별 상담 빈도 + 공통 주제 키워드 + 미상담 학생.
      def analyze(sources)
        # 1. 학생별 상담 빈도 — entity_mentions ⨝ entities (type=student) 활용
        entry_ids = sources.map { |s| s[:id] }
        student_counts = if entry_ids.any?
          @db[:entity_mentions]
            .join(:entities, id: :entity_id)
            .where(Sequel[:entity_mentions][:entry_id] => entry_ids,
              Sequel[:entities][:type] => "student")
            .group_and_count(Sequel[:entities][:name])
            .order(Sequel.desc(:count))
            .all
            .map { |r| [r[:name], r[:count]] }
        else
          []
        end

        # 2. 공통 주제 키워드 — 모든 본문 합쳐서 빈도 분석
        all_text = sources.map { |s| s[:body] }.join("\n")
        keywords = extract_topic_keywords(all_text)

        # 3. 미상담 학생 — class_roster vs student_counts
        roster = (Core::Settings.load["class_roster"] || []).reject { |n| n.to_s.strip.empty? }
        consulted = student_counts.map(&:first).to_set
        unconsulted = roster.reject { |name| consulted.include?(name) }

        {
          student_counts: student_counts,
          keywords: keywords,
          unconsulted: unconsulted,
          roster_size: roster.size,
          consulted_size: consulted.size
        }
      end

      def extract_topic_keywords(text)
        tokens = text.split(/[\s.,!?。()\[\]「」『』【】\-—–:;]+/).reject(&:empty?)
        freq = Hash.new(0)
        tokens.each do |token|
          stem = strip_particle(token)
          next if stem.length < 2
          next if STOPWORDS.include?(stem)
          next unless stem.match?(/\p{Hangul}/)
          freq[stem] += 1
        end
        freq.sort_by { |_, c| -c }.first(TOP_KEYWORD_N).map { |w, c| {word: w, count: c} }
      end

      def strip_particle(token)
        KOREAN_PARTICLES.each do |p|
          if token.length > p.length && token.end_with?(p)
            return token[0...-p.length]
          end
        end
        token
      end

      def synthesize_deterministic(_semester_label, sources, analysis, _since_t, _until_t)
        lines = []
        lines << "## 📊 학기 상담 통계"
        lines << ""
        lines << "- 총 상담 entries: **#{sources.size}건**"
        lines << "- 상담받은 학생: **#{analysis[:consulted_size]}명** (학급 명단 #{analysis[:roster_size]}명 중)"
        lines << ""

        lines << "## 👥 학생별 상담 빈도"
        lines << ""
        if analysis[:student_counts].any?
          analysis[:student_counts].each do |name, n|
            lines << "- **#{name}**: #{n}회"
          end
        else
          lines << "_학생 entity 인덱스 없음 — `ExtractEntities` 실행 필요._"
        end
        lines << ""

        if analysis[:unconsulted].any?
          lines << "## 🌱 아직 면담하지 않은 학생 (학급 명단 기준)"
          lines << ""
          lines << "_상담 우선순위 후보 — 학급 명단에 등록됐지만 학기 동안 상담 기록이 없는 학생들._"
          lines << ""
          analysis[:unconsulted].each { |name| lines << "- #{name}" }
          lines << ""
        end

        lines << "## 🔤 자주 등장한 주제 키워드 (상위 #{TOP_KEYWORD_N})"
        lines << ""
        if analysis[:keywords].any?
          analysis[:keywords].each do |kw|
            lines << "- `#{kw[:word]}` × #{kw[:count]}"
          end
        else
          lines << "_키워드 추출 결과 없음._"
        end
        lines << ""

        lines << "## 📅 학기 상담 timeline"
        lines << ""
        sources.each_with_index do |s, i|
          icon = mode_icon(s[:mode])
          cat = s[:category].to_s.empty? ? "" : " · #{s[:category]}"
          lines << "### [#{i + 1}] #{s[:created_at].to_s[0, 10]} #{icon}#{cat}"
          lines << ""
          lines << "> #{s[:excerpt]}"
          lines << ""
          lines << "출처: [[#{s[:path]}]]"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (시간순 인용 + 학생/키워드 빈도 + 학급 명단 비교)._"
        lines << "_가족·학습 환경 패턴, 다음 학기 우선 면담 제안 분석은 LLM 모드에서._"
        lines << "_각 통계는 *원자료* — 면담 자리에서는 교사의 직접 판단·맥락이 우선._"
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

      def synthesize_via_llm(semester_label, sources, analysis, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(semester_label, sources, analysis, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(semester_label, sources, analysis, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 학기 학부모 상담 패턴을 정리합니다.
          입력: 학기 상담 timeline + 학생별 빈도 + 공통 키워드 + 미상담 학생.
          톤: 객관적·관찰. 단정·낙인 금지. 학부모/학생 사적 평가 금지.
          본문에 없는 사실 만들기 금지.

          출력 마크다운 (모든 섹션 포함):
          ## 📊 학기 상담 흐름 (1~2 문장)

          ## 🏠 가족 환경 패턴 (관찰)
          - 본문에 명시된 사실만, 인용 [#] + 단정 X

          ## 🎓 학습 환경 패턴 (관찰)
          - 본문에 명시된 사실만

          ## 💡 다음 학기 우선 면담 후보 (제안)
          - 미상담 학생 목록 기반 1~3 명, "면담을 검토해 보세요" 톤
          - 강요 X — 교사 판단 우선

          분량: 500~1500자.
        TXT
      end

      def llm_user_prompt(semester_label, sources, analysis, since_t, until_t)
        timeline = sources.first(20).map.with_index { |s, i|
          "[#{i + 1}] #{s[:created_at].to_s[0, 10]} #{mode_icon(s[:mode])}: #{s[:excerpt]}"
        }.join("\n")
        student_text = analysis[:student_counts].first(10).map { |n, c| "#{n}(#{c}회)" }.join(", ")
        keyword_text = analysis[:keywords].map { |kw| "#{kw[:word]}(#{kw[:count]})" }.join(", ")
        unconsulted_text = analysis[:unconsulted].first(10).join(", ")
        <<~TXT
          # 학기: #{semester_label}
          # 기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}
          # 총 상담 entries: #{sources.size}건

          # 학생별 상담 빈도 (상위 10)
          #{student_text.empty? ? "(없음)" : student_text}

          # 자주 등장한 주제 키워드
          #{keyword_text.empty? ? "(없음)" : keyword_text}

          # 미상담 학생 (학급 명단 기준)
          #{unconsulted_text.empty? ? "(없음 — 모든 학생 상담 완료)" : unconsulted_text}

          # 학기 상담 timeline (최대 20)
          #{timeline}
        TXT
      end

      def build_full_content(semester_label, body, sources, analysis, since_t, until_t, cats)
        fm = {
          "is_synth" => true,
          "synth_target" => "parent-patterns:#{semester_label}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => sources.size,
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_categories" => cats,
          "synth_consulted_count" => analysis[:consulted_size],
          "synth_roster_size" => analysis[:roster_size],
          "synth_unconsulted_count" => analysis[:unconsulted].size,
          "synth_model" => synth_model_label,
          "title" => "학부모 상담 패턴 (#{semester_label})"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 학부모 상담 패턴 — #{semester_label}\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target(semester_label)
        @vault_dir.join(SYNTH_DIR, "#{semester_label}.md")
      end
    end
  end
end
