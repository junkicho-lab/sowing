# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 자기 회고 패턴 — 교사 자신의 *집필 패턴* 메타-합성 (확장 합성기 #10).
    #
    # 다른 합성기들은 학생·수업·연수·학부모 등 *외부* 분석.
    # 이건 *교사 본인* 에 대한 분석 — 어떻게 쓰는가, 무엇을 자주 환기하는가.
    #
    # 입력: 모든 entries (또는 window) — 본인이 쓴 본문 전체
    # 출력:
    #   - 결정적: 모드/카테고리 분포 + 일별 작성 시간대 + 긍정/부정 어휘 빈도 +
    #     평균 문장 길이 + 자주 등장하는 토픽 키워드 + 연속 작성/공백 기간
    #   - LLM: 집필 시기 톤 변화 / 잠재적 burnout 시그널 (없는 표현·줄어든 빈도) /
    #          미발견 주제 / 다음 학기에 의도적으로 시도해 볼 만한 것
    #
    # 자율 판단 0 (ADR-013):
    #   - "이 교사는 ~ 한 사람이다" 단정 X — 통계 + 인용만
    #   - "지쳤어요" 같은 감정 단정 X — "최근 4주간 '힘들다' 표현 N건" 같이 *사실*
    #   - burnout 시그널도 *후보* 로만 — 강한 단정 거부
    #
    # 저장 위치: vault/.sowing/synth/self-patterns/{period_label}.md
    class SynthesizeSelfPatterns
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/self-patterns"
      DEFAULT_WINDOW_DAYS = 180
      MIN_ENTRIES = 10  # 패턴 분석에 의미 있는 최소
      MAX_ENTRIES = 5_000
      EXCERPT_LIMIT = 200
      TOP_KEYWORD_N = 15

      # 긍정/부정 신호어 — Phase 12 LessonPattern 의 dictionary 재사용 + 자기 회고 톤 추가.
      POSITIVE = %w[
        잘됐 성공 좋았 활기 집중 흥미 참여 효과적 만족 보람 자발 적극 협력
        몰입 감동 뿌듯 행복 즐거 신기 멋지 사랑스러 기특 자랑스러
      ].freeze
      NEGATIVE = %w[
        어려웠 힘들 산만 부족 아쉬웠 실패 혼란 지루 소극적 시간\ 부족
        피곤 지친 무거 답답 막막 막혀 슬프 외로 우울 짜증 걱정 불안
      ].freeze
      NEGATION_RE = /(?:안|못|없|지 못|하지 못)/

      # 자기 회고 도메인 불용어 — 키워드 추출 시 제외.
      STOPWORDS = %w[
        오늘 내일 어제 학생 학생들 우리 모두 수업 시간 활동 정리 진행 이번
        다음 지난 이런 그런 저런 어떤 모든 같은 다른 새로 처음
        내용 결과 사항 부분 경우 정도 만큼 보다 위해 통해 대해 관해
        있다 없다 하다 되다 이다 그러다 그렇다 좋다 어렵다 같다 다르다
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

      # @param period_label [String] 기간 라벨 (예: "2026-1학기", "최근-1년")
      # @param since [Time, String, nil]
      # @param until_time [Time, String, nil]
      # @return [Result] Success(Pathname) | Failure(:no_entries | :too_many_entries)
      def call(period_label:, since: nil, until_time: nil)
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        rows = @db[:entries]
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .order(:created_at)
          .all
        return Failure(:no_entries) if rows.size < MIN_ENTRIES
        return Failure(:too_many_entries) if rows.size > MAX_ENTRIES

        analysis = analyze(rows, since_t, until_t)

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(period_label, analysis, since_t, until_t)
          }
        else
          synthesize_deterministic(period_label, analysis, since_t, until_t)
        end

        target = vault_target(period_label)
        content = build_full_content(period_label, body, analysis, since_t, until_t)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      def analyze(rows, since_t, until_t)
        mode_counts = rows.group_by { |r| r[:mode] }.transform_values(&:count)
        category_counts = rows.map { |r| r[:category].to_s }.reject(&:empty?).tally
          .sort_by { |_, n| -n }.first(10)

        # 시간대 분포 — 작성 시각의 hour
        hour_counts = Hash.new(0)
        rows.each { |r| hour_counts[Time.parse(r[:created_at].to_s).hour] += 1 }

        # 작성 공백 기간 — 연속 빈 날 (sliding window)
        dates = rows.map { |r| r[:created_at].to_s[0, 10] }.uniq.sort
        gaps = compute_gaps(dates, since_t.to_date, until_t.to_date)

        # 본문 어휘 분석 — 긍정/부정 신호어 카운트, 토픽 키워드, 평균 문장 길이
        all_text = rows.map { |r| read_body(r[:path]) }.reject(&:empty?).join("\n")
        positive_count = count_signal_words(all_text, POSITIVE)
        negative_count = count_signal_words(all_text, NEGATIVE)
        keywords = extract_topic_keywords(all_text)
        avg_sentence_length = compute_avg_sentence_length(all_text)

        # 최근 4주 vs 그 이전 — 긍정/부정 비율 변화 (burnout 시그널 단서)
        cutoff = until_t - 28 * 86_400
        recent_rows = rows.select { |r| Time.parse(r[:created_at].to_s) >= cutoff }
        older_rows = rows - recent_rows
        recent_signals = signal_ratios(recent_rows)
        older_signals = signal_ratios(older_rows)

        {
          total: rows.size,
          mode_counts: mode_counts,
          category_counts: category_counts,
          hour_counts: hour_counts.sort.to_h,
          peak_hour: hour_counts.max_by { |_, c| c }&.first,
          gaps: gaps,
          positive_count: positive_count,
          negative_count: negative_count,
          keywords: keywords,
          avg_sentence_length: avg_sentence_length,
          recent_signals: recent_signals,
          older_signals: older_signals,
          recent_count: recent_rows.size,
          older_count: older_rows.size
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

      # 부정 윈도 5자 필터 적용 — "잘 안 됐다" 의 "잘" 매칭 무효화.
      def count_signal_words(text, keywords)
        count = 0
        text.split(/[.!?。\n]+/).each do |sent|
          keywords.each do |kw|
            pattern = kw.gsub('\\ ', " ")
            idx = sent.index(pattern)
            next unless idx

            window_before = sent[[idx - 5, 0].max...idx]
            window_after = sent[(idx + pattern.length)...(idx + pattern.length + 5)]
            window = "#{window_before}#{window_after}"
            count += 1 unless window.match?(NEGATION_RE)
          end
        end
        count
      end

      def signal_ratios(rows)
        return {positive: 0, negative: 0, total: 0} if rows.empty?
        text = rows.map { |r| read_body(r[:path]) }.reject(&:empty?).join("\n")
        {
          positive: count_signal_words(text, POSITIVE),
          negative: count_signal_words(text, NEGATIVE),
          total: rows.size
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

      def compute_avg_sentence_length(text)
        sentences = text.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?)
        return 0 if sentences.empty?
        (sentences.sum(&:length).to_f / sentences.size).round(1)
      end

      def compute_gaps(written_dates_str, since_date, until_date)
        written = written_dates_str.map { |s| Date.parse(s) }.to_set
        gaps = []
        current_gap_start = nil
        (since_date..until_date).each do |date|
          if written.include?(date)
            if current_gap_start
              gap_days = (date - current_gap_start).to_i
              gaps << {start: current_gap_start.to_s, end: (date - 1).to_s, days: gap_days} if gap_days >= 7
              current_gap_start = nil
            end
          else
            current_gap_start ||= date
          end
        end
        # 마지막 gap 처리
        if current_gap_start
          gap_days = (until_date - current_gap_start).to_i + 1
          gaps << {start: current_gap_start.to_s, end: until_date.to_s, days: gap_days} if gap_days >= 7
        end
        gaps.sort_by { |g| -g[:days] }.first(5)
      end

      def synthesize_deterministic(_period_label, a, since_t, until_t)
        lines = []
        lines << "## 📊 기본 통계"
        lines << ""
        lines << "- 기간: **#{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}**"
        lines << "- 총 entries: **#{a[:total]}건**"
        lines << "- 모드별: " + a[:mode_counts].map { |m, n| "#{mode_icon(m)} #{n}" }.join(" · ")
        lines << "- 평균 문장 길이: #{a[:avg_sentence_length]} 자"
        lines << ""

        lines << "## 🕐 작성 시간대 분포"
        lines << ""
        if a[:peak_hour]
          peak = a[:hour_counts][a[:peak_hour]]
          lines << "- 가장 자주 쓴 시간: **#{a[:peak_hour]}시** (#{peak}건)"
        end
        lines << "- 시간대별 카운트:"
        (0..23).step(2) do |h|
          c1 = a[:hour_counts][h] || 0
          c2 = a[:hour_counts][h + 1] || 0
          total = c1 + c2
          bar = "▌" * [total, 30].min
          lines << "  - #{format("%02d", h)}~#{format("%02d", h + 1)}시: #{bar} #{total}" if total > 0
        end
        lines << ""

        lines << "## 📚 자주 다룬 카테고리 (상위 10)"
        lines << ""
        if a[:category_counts].any?
          a[:category_counts].each { |cat, n| lines << "- **#{cat}**: #{n}건" }
        else
          lines << "_카테고리 정보 없음._"
        end
        lines << ""

        lines << "## 🔤 자주 등장한 토픽 키워드 (상위 #{TOP_KEYWORD_N})"
        lines << ""
        if a[:keywords].any?
          a[:keywords].each { |kw| lines << "- `#{kw[:word]}` × #{kw[:count]}" }
        else
          lines << "_키워드 추출 결과 없음._"
        end
        lines << ""

        lines << "## 🌗 톤 신호어 카운트 (부정 윈도 필터 적용)"
        lines << ""
        lines << "- 긍정 신호어: **#{a[:positive_count]}건** (좋았/효과적/뿌듯/보람 등)"
        lines << "- 부정 신호어: **#{a[:negative_count]}건** (힘들/어려웠/지친/막막 등)"
        if a[:positive_count] + a[:negative_count] > 0
          pos_ratio = a[:positive_count].to_f / (a[:positive_count] + a[:negative_count])
          lines << "- 비율: 긍정 #{(pos_ratio * 100).round(1)}% / 부정 #{((1 - pos_ratio) * 100).round(1)}%"
        end
        lines << ""

        lines << "## 📈 최근 4주 vs 이전 — 톤 변화"
        lines << ""
        rs = a[:recent_signals]
        os = a[:older_signals]
        lines << "| 기간 | entries | 긍정 | 부정 |"
        lines << "|------|---------|------|------|"
        lines << "| 이전 (#{a[:older_count]} entries) | #{os[:total]} | #{os[:positive]} | #{os[:negative]} |"
        lines << "| 최근 4주 (#{a[:recent_count]} entries) | #{rs[:total]} | #{rs[:positive]} | #{rs[:negative]} |"
        lines << ""

        if a[:gaps].any?
          lines << "## 📅 작성 공백 (7일 이상, 상위 5)"
          lines << ""
          lines << "_쓰지 않은 기간 — 바빴거나, 다른 일에 집중했거나, 의도적 쉼._"
          lines << ""
          a[:gaps].each do |g|
            lines << "- **#{g[:days]}일**: #{g[:start]} ~ #{g[:end]}"
          end
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (통계 + 신호어 빈도 + 시간 분포)._"
        lines << "_집필 톤 변화, 잠재적 burnout 시그널, 미발견 주제 분석은 LLM 모드에서._"
        lines << "_단정 거부: \"교사가 지쳤다\" X → \"부정 신호어 N건\" O. 해석은 본인이._"
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

      def synthesize_via_llm(period_label, analysis, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(period_label, analysis, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(period_label, analysis, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사의 *집필 패턴* 을 메타 분석합니다.
          입력: 기간 통계 + 모드 분포 + 시간대 + 토픽 키워드 + 긍정/부정 신호어 +
            최근 4주 vs 이전 비교 + 작성 공백.
          톤: 객관적·따뜻함. *교사 자신* 에 대한 단정 금지 — 감정 추측 금지.
          본문에 없는 사실 만들기 금지.

          출력 마크다운 (모든 섹션 포함):
          ## 🌊 집필 시기별 톤 변화 (사실 기반)
          - 최근 4주 vs 이전 비교 1~2 문장. 단정 X.

          ## 💡 자주 환기되는 주제 (관찰)
          - 키워드 빈도에서 보이는 1~3 주제.

          ## 🌱 잠재적 burnout 시그널 (후보)
          - 부정 신호어 증가 / 작성 공백 등을 *사실로만* 표기.
          - "지쳤어요" 단정 X — "최근 4주간 부정 표현 N건" O
          - 시그널이 없으면 솔직히 "특별한 시그널 없음" 표기.

          ## 💭 다음 학기 의도적 시도 후보 (제안)
          - 미발견 주제 (키워드에 없는 카테고리) 1~3개.
          - 강요 X — "검토해 보면 어떨까요" 톤.

          분량: 500~1200자.
        TXT
      end

      def llm_user_prompt(period_label, a, since_t, until_t)
        <<~TXT
          # 기간: #{period_label} (#{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]})
          # 총 #{a[:total]}건 (memo #{a[:mode_counts]["memo"] || 0} · note #{a[:mode_counts]["note"] || 0} · record #{a[:mode_counts]["record"] || 0})

          # 자주 다룬 카테고리
          #{a[:category_counts].map { |c, n| "#{c}(#{n})" }.join(", ")}

          # 자주 등장한 토픽 키워드
          #{a[:keywords].map { |kw| "#{kw[:word]}(#{kw[:count]})" }.join(", ")}

          # 톤 신호어 — 부정 윈도 5자 필터 적용
          긍정 #{a[:positive_count]}건 / 부정 #{a[:negative_count]}건

          # 최근 4주 vs 이전
          - 이전: entries #{a[:older_count]} · 긍정 #{a[:older_signals][:positive]} · 부정 #{a[:older_signals][:negative]}
          - 최근 4주: entries #{a[:recent_count]} · 긍정 #{a[:recent_signals][:positive]} · 부정 #{a[:recent_signals][:negative]}

          # 시간대 분포 (peak)
          #{a[:peak_hour]}시

          # 작성 공백 (7일+)
          #{a[:gaps].map { |g| "#{g[:days]}일 (#{g[:start]} ~ #{g[:end]})" }.join(", ")}
        TXT
      end

      def build_full_content(period_label, body, analysis, since_t, until_t)
        fm = {
          "is_synth" => true,
          "synth_target" => "self-patterns:#{period_label}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => analysis[:total],
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_positive_count" => analysis[:positive_count],
          "synth_negative_count" => analysis[:negative_count],
          "synth_gap_count" => analysis[:gaps].size,
          "synth_model" => synth_model_label,
          "title" => "자기 회고 패턴: #{period_label}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 자기 회고 패턴 — #{period_label}\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target(period_label)
        @vault_dir.join(SYNTH_DIR, "#{period_label}.md")
      end
    end
  end
end
