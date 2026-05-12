# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 자기 거울 — 5축 자아 분석 (Phase 13 W28-T01, 17번째 합성기).
    #
    # SelfPatterns(#10) 와 차이:
    # - SelfPatterns: 큰 기간 (학기·1년) 의 집필 패턴 메타-분석
    # - SelfMirror:   짧은 기간 (1일·1주) 의 즉각적 5축 거울
    #
    # 5축 (지독한 기록 의 김교수 영상 영감 + 단정 거부):
    #   1. 지성: 자주 환기한 키워드 top 5
    #   2. 감정: POSITIVE/NEGATIVE 신호어 카운트 + 비율
    #   3. 습관: 작성 시간대 + 카테고리 분포
    #   4. 관계: entity_mentions top 5 (학생·동료·학부모)
    #   5. 에너지: 작성 빈도 + 공백
    #
    # 자율 판단 0 (ADR-013):
    #   - "당신은 ~ 한 사람" 단정 X — 통계와 인용만
    #   - "지쳤네요" 감정 단정 X — "부정 신호어 N건" 같은 사실
    #   - LLM 출력도 5축 해석 *후보* 로만, 단정 거부 톤
    #
    # 저장 위치: vault/.sowing/synth/self-mirror/{period}-{date}.md
    #   - daily-2026-05-11.md  (1일 분석)
    #   - weekly-2026-W19.md   (7일 분석)
    class SynthesizeSelfMirror
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/self-mirror"
      PERIODS = %i[daily weekly].freeze
      DEFAULT_PERIOD = :daily
      MIN_ENTRIES = 3   # 5축 분석 최소 — daily 라 적게 시작 가능
      MAX_ENTRIES = 500
      TOP_KEYWORD_N = 5
      TOP_RELATION_N = 5

      # 신호어 — SynthesizeSelfPatterns 에서 재사용 (코드 중복 X).
      POSITIVE = SynthesizeSelfPatterns::POSITIVE
      NEGATIVE = SynthesizeSelfPatterns::NEGATIVE
      STOPWORDS = SynthesizeSelfPatterns::STOPWORDS
      KOREAN_PARTICLES = SynthesizeSelfPatterns::KOREAN_PARTICLES

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

      # @param period [Symbol] :daily 또는 :weekly
      # @param date [String] daily="YYYY-MM-DD" / weekly="YYYY-Www"
      # @return [Result] Success(Pathname) | Failure(:invalid_period | :no_entries | :too_many)
      def call(period: DEFAULT_PERIOD, date: nil)
        period = period.to_sym
        return Failure(:invalid_period) unless PERIODS.include?(period)

        date ||= default_date_for(period)
        since_t, until_t = window_for(period, date)

        rows = @db[:entries]
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .order(:created_at)
          .all
        return Failure(:no_entries) if rows.size < MIN_ENTRIES
        return Failure(:too_many) if rows.size > MAX_ENTRIES

        analysis = analyze_5_axes(rows, since_t, until_t)

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(period, date, analysis)
          }
        else
          synthesize_deterministic(period, date, analysis)
        end

        target = write_synth(period, date, body, analysis, rows.size)
        Success(target)
      end

      private

      def default_date_for(period)
        case period
        when :daily  then @clock.now.strftime("%Y-%m-%d")
        when :weekly then @clock.now.strftime("%Y-W%V")
        end
      end

      def window_for(period, date)
        case period
        when :daily
          d = Date.parse(date)
          [Time.new(d.year, d.month, d.day, 0, 0, 0),
            Time.new(d.year, d.month, d.day, 23, 59, 59)]
        when :weekly
          # date = "2026-W19" → 그 주의 월요일~일요일
          year, week = date.match(/\A(\d{4})-W(\d{2})\z/).captures.map(&:to_i)
          monday = Date.commercial(year, week, 1)
          sunday = Date.commercial(year, week, 7)
          [Time.new(monday.year, monday.month, monday.day, 0, 0, 0),
            Time.new(sunday.year, sunday.month, sunday.day, 23, 59, 59)]
        end
      end

      # 5축 분석 — 결정적 통계.
      def analyze_5_axes(rows, since_t, until_t)
        bodies = load_bodies(rows)
        full_text = bodies.join("\n")

        {
          intellect: top_keywords(full_text),
          emotion: count_signals(full_text),
          habit: {
            hour_distribution: hour_distribution(rows),
            category_distribution: category_distribution(rows),
            mode_distribution: mode_distribution(rows)
          },
          relationship: top_relations(rows),
          energy: {
            entry_count: rows.size,
            avg_per_day: rows.size.to_f / days_in_window(since_t, until_t),
            written_dates: rows.map { |r| Time.parse(r[:created_at].to_s).to_date }.uniq
          }
        }
      end

      def load_bodies(rows)
        rows.filter_map { |r|
          path = @vault_dir.join(r[:path])
          next nil unless path.exist?
          File.read(path, encoding: "UTF-8").sub(/\A---\n.*?\n---\n+/m, "")
        }
      end

      def top_keywords(text)
        # 한국어 2글자 이상 명사 후보 — 조사 떼고 stopword 제거 + 빈도
        words = text.scan(/[가-힣A-Za-z]{2,}/)
        words.map! { |w| strip_particle(w) }
        words.reject! { |w| STOPWORDS.include?(w) || w.length < 2 }
        counts = words.tally
        counts.sort_by { |_, c| -c }.first(TOP_KEYWORD_N).map { |w, c| {word: w, count: c} }
      end

      def strip_particle(word)
        KOREAN_PARTICLES.each do |p|
          return word.sub(/#{p}\z/, "") if word.end_with?(p) && word.length > p.length + 1
        end
        word
      end

      def count_signals(text)
        pos = POSITIVE.sum { |w| text.scan(w).size }
        neg = NEGATIVE.sum { |w|
          # 부정어 (안/못/없) 가 앞 5자 안에 있으면 카운트 제외
          text.enum_for(:scan, w).map { Regexp.last_match }
            .count { |m| !text[[m.begin(0) - 5, 0].max...m.begin(0)].match?(/(안|못|없)/) }
        }
        total = pos + neg
        ratio = (total > 0) ? (pos.to_f / total * 100).round(1) : nil
        {positive: pos, negative: neg, total: total, positive_ratio: ratio}
      end

      def hour_distribution(rows)
        counts = Array.new(24, 0)
        rows.each { |r| counts[Time.parse(r[:created_at].to_s).hour] += 1 }
        counts
      end

      def category_distribution(rows)
        rows.map { |r| r[:category] }.compact.tally.sort_by { |_, c| -c }.first(5)
      end

      def mode_distribution(rows)
        rows.map { |r| r[:mode] }.tally
      end

      def top_relations(rows)
        # entity_mentions 테이블 — Phase 11 student entity 시스템 재사용
        entry_ids = rows.map { |r| r[:id] }
        return [] if entry_ids.empty?
        mentions = @db[:entity_mentions]
          .where(entry_id: entry_ids)
          .join(:entities, id: :entity_id)
          .select_group(Sequel[:entities][:name].as(:name))
          .select_append { count(Sequel[:entity_mentions][:id]).as(:count) }
          .order(Sequel.desc(:count))
          .limit(TOP_RELATION_N)
          .all
        mentions.map { |m| {name: m[:name], count: m[:count]} }
      rescue Sequel::DatabaseError
        []  # entities 테이블 부재 시 빈 배열
      end

      def days_in_window(since_t, until_t)
        ((until_t - since_t) / 86_400.0).ceil.to_i.clamp(1, 365)
      end

      def synthesize_deterministic(period, date, a)
        period_label = (period == :daily) ? "오늘" : "이번 주"
        lines = []
        lines << "# 🪞 자기 거울 — #{period_label} (#{date})"
        lines << ""
        lines << "총 #{a[:energy][:entry_count]}건 작성. 일평균 #{a[:energy][:avg_per_day].round(1)}건."
        lines << ""
        lines << "## 1. 🧠 지성 — 자주 환기한 키워드"
        lines << ""
        if a[:intellect].empty?
          lines << "- (키워드 부족)"
        else
          a[:intellect].each { |k| lines << "- **#{k[:word]}** (#{k[:count]}회)" }
        end
        lines << ""
        lines << "## 2. 💭 감정 — 신호어 카운트"
        lines << ""
        em = a[:emotion]
        lines << "- 긍정 신호어: **#{em[:positive]}건**"
        lines << "- 부정 신호어: **#{em[:negative]}건**"
        if em[:positive_ratio]
          lines << "- 긍정 비율: **#{em[:positive_ratio]}%** (전체 #{em[:total]}건 중)"
        end
        lines << ""
        lines << "## 3. 🔁 습관 — 시간대·카테고리"
        lines << ""
        peak_hour = a[:habit][:hour_distribution].each_with_index.max_by { |c, _| c }
        lines << "- 가장 자주 쓴 시간대: **#{peak_hour[1]}시** (#{peak_hour[0]}건)"
        if a[:habit][:category_distribution].any?
          cats = a[:habit][:category_distribution].map { |c, n| "#{c}(#{n})" }.join(" · ")
          lines << "- 카테고리 분포: #{cats}"
        end
        modes = a[:habit][:mode_distribution]
        lines << "- 모드: 💭메모 #{modes["memo"] || 0} · 📝필기 #{modes["note"] || 0} · 📖기록 #{modes["record"] || 0}"
        lines << ""
        lines << "## 4. 🤝 관계 — 자주 언급한 사람"
        lines << ""
        if a[:relationship].empty?
          lines << "- (학생·동료 entity 부재 — 학급 명단 설정 권장)"
        else
          a[:relationship].each { |r| lines << "- **#{r[:name]}** (#{r[:count]}회)" }
        end
        lines << ""
        lines << "## 5. ⚡ 에너지 — 작성 패턴"
        lines << ""
        lines << "- 작성한 날짜: **#{a[:energy][:written_dates].size}일**"
        lines << "- 총 entries: **#{a[:energy][:entry_count]}건**"
        lines << ""
        lines << "---"
        lines << ""
        lines << "💡 **단정 거부** — 위는 통계와 사실만. 해석은 본인의 몫. " \
                "지속적인 패턴이 보이면 [/synth/self-patterns](/synth) 의 장기 분석을 참고하세요."
        lines << ""
        lines << "*결정적 합성 — LLM 키 설정 시 5축 종합 해석 추가 가능.*"
        lines.join("\n")
      end

      def synthesize_via_llm(period, date, a)
        system = <<~SYS
          당신은 한국 초등 교사의 짧은 자기 거울을 보조하는 도구입니다.
          5축 통계만 받고 200~400자로 자연어 해석을 제공합니다.
          절대 규칙:
          - "당신은 ~ 한 사람이다" 단정 X
          - "지치셨네요" 같은 감정 단정 X — 통계는 통계로만
          - 모든 해석을 *후보* 또는 *경향* 으로 표현
          - 의인화·과잉 공감 X
          - 5축 모두 짧게 다루되 균형 있게
        SYS
        user = <<~USR
          기간: #{period} #{date}
          작성: #{a[:energy][:entry_count]}건 (#{a[:energy][:written_dates].size}일)

          1. 지성 (키워드 top): #{a[:intellect].map { |k| "#{k[:word]}(#{k[:count]})" }.join(", ")}
          2. 감정: 긍정 #{a[:emotion][:positive]} / 부정 #{a[:emotion][:negative]} (긍정 #{a[:emotion][:positive_ratio]}%)
          3. 습관: 카테고리 #{a[:habit][:category_distribution].map { |c, n| "#{c}(#{n})" }.join(", ")} / 모드 #{a[:habit][:mode_distribution].inspect}
          4. 관계: #{a[:relationship].map { |r| "#{r[:name]}(#{r[:count]})" }.join(", ")}
          5. 에너지: 일평균 #{a[:energy][:avg_per_day].round(1)}건

          위 5축 통계를 200~400자로 *부드럽고 단정 거부* 한 톤으로 해석해주세요.
          각 축에 한두 문장씩, 마지막에 한 문장 의도적 시도 제안.
        USR

        # LLM 호출 — 결정적 분석 + LLM 해석 결합
        llm_text = @llm_backend.chat(system: system, user: user)
        deterministic = synthesize_deterministic(period, date, a)
        # LLM 결과를 결정적 본문 위에 prepend
        "#{deterministic.sub(/\*결정적 합성.*\z/m, "")}\n\n---\n\n## 🌅 5축 종합 해석 (LLM)\n\n#{llm_text}\n"
      end

      def write_synth(period, date, body, analysis, source_count)
        rel = "#{SYNTH_DIR}/#{period}-#{date}.md"
        target = @vault_dir.join(rel)
        FileUtils.mkdir_p(target.dirname)

        fm = {
          "is_synth" => true,
          "synth_target" => "self-mirror:#{period}-#{date}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => source_count,
          "synth_period" => period.to_s,
          "synth_period_date" => date,
          "synth_positive_count" => analysis[:emotion][:positive],
          "synth_negative_count" => analysis[:emotion][:negative],
          "synth_relation_count" => analysis[:relationship].size,
          "synth_model" => @llm_backend ? "Anthropic" : "deterministic",
          "title" => "자기 거울: #{period == :daily ? "오늘" : "이번 주"} (#{date})"
        }
        yaml = YAML.dump(fm).delete_prefix("---\n")
        @safe_writer.atomic_write(target, "---\n#{yaml}---\n\n#{body}\n")
        target
      end
    end
  end
end
