# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 학습 진척 추이 (확장 합성기 #11).
    #
    # vs 기존 #6 SynthesizeLessonSeries (단원 차시 timeline):
    #   - LessonSeries: 키워드 기반 차시 timeline + 단원 종료 자동 감지 + 학생 반응
    #   - #11 LearningProgress: **페이스 분석** (차시 간격 분포) + 누적 곡선 +
    #     **학습 활동 분포** (수업/평가/회고 비율) + 진행 상태 판정
    #
    # 입력: keyword (예: "분수", "협동학습") + 시간 window (default 6개월)
    #   - title 또는 body 매칭 entries 시간순
    #
    # 결정적 출력:
    #   - 차시 timeline (시간순 + mode 아이콘 + 출처)
    #   - **차시 간격 분포** — 평균/최대/최소 일수, consistency 지표
    #   - **누적 곡선** — 시간순 누적 차시 수 (text bar chart)
    #   - **학습 활동 분포** — record/note/memo 비율 + 카테고리별 분포
    #   - **진행 상태** — 마지막 차시 후 경과 + 진행 중 vs 종료 vs 휴면
    #
    # LLM 옵트인 출력 4 섹션:
    #   - 학습 페이스 평가 (객관적 — 빠름/느림/일정 등)
    #   - 활동 균형 분석 (수업 vs 회고 vs 평가)
    #   - 학습 cohort (자주 등장한 학생들)
    #   - 다음 차시 우선순위 제안 (계획·실행)
    #
    # 자율 판단 0:
    #   - "이 학생이 학습 부진" 같은 단정 X — 차시 카운트 + 페이스 통계만
    #   - 진행 상태 판정도 *경과일 통계 기반* (단정 X)
    #
    # 저장 위치: vault/.sowing/synth/learning-progress/{slug}.md
    class SynthesizeLearningProgress
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/learning-progress"
      DEFAULT_WINDOW_DAYS = 180  # 6개월
      MIN_ENTRIES = 3
      MAX_ENTRIES = 200
      EXCERPT_LIMIT = 160
      DORMANT_AFTER_DAYS = 30   # 마지막 차시 후 30일 → 휴면
      ENDED_AFTER_DAYS = 60      # 60일 → 종료

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

      # @param keyword [String] 학습 단원·주제 키워드
      # @param since [Time, String, nil]
      # @param until_time [Time, String, nil]
      # @return [Result] Success(Pathname) | Failure(:invalid_keyword | :no_entries | :too_many_entries)
      def call(keyword:, since: nil, until_time: nil)
        return Failure(:invalid_keyword) if keyword.to_s.strip.empty?

        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        candidate_rows = @db[:entries]
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .order(:created_at)
          .all

        matched = candidate_rows.select { |row|
          next true if row[:title].to_s.include?(keyword)
          read_body(row[:path]).include?(keyword)
        }
        return Failure(:no_entries) if matched.size < MIN_ENTRIES
        return Failure(:too_many_entries) if matched.size > MAX_ENTRIES

        analysis = analyze(matched, until_t)

        body = if @llm_backend
          Infrastructure::AuditLog.with_actor("agent") {
            synthesize_via_llm(keyword, matched, analysis, since_t, until_t)
          }
        else
          synthesize_deterministic(keyword, matched, analysis, since_t, until_t)
        end

        target = vault_target(keyword)
        content = build_full_content(keyword, body, matched, analysis, since_t, until_t)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      def read_body(rel_path)
        abs = @vault_dir.join(rel_path)
        return "" unless abs.exist?
        parsed = @parser.call(abs.read)
        parsed.content.to_s
      rescue
        ""
      end

      def analyze(rows, until_t)
        # 차시 간격 (일 단위)
        dates = rows.map { |r| Date.parse(r[:created_at].to_s) }
        intervals = dates.each_cons(2).map { |a, b| (b - a).to_i }

        avg_interval = intervals.empty? ? nil : (intervals.sum.to_f / intervals.size).round(1)
        max_interval = intervals.max
        min_interval = intervals.min

        # 진행 상태 — 마지막 차시 후 경과
        days_since_last = (until_t.to_date - dates.last).to_i
        status =
          if days_since_last >= ENDED_AFTER_DAYS then :ended
          elsif days_since_last >= DORMANT_AFTER_DAYS then :dormant
          else :active
          end

        # 모드 분포
        mode_counts = rows.group_by { |r| r[:mode] }.transform_values(&:count)
        category_counts = rows.map { |r| r[:category].to_s }.reject(&:empty?).tally
          .sort_by { |_, n| -n }.first(8)

        # 학습 cohort — entity_mentions ⨝ entities (type=student)
        entry_ids = rows.map { |r| r[:id] }
        cohort = if entry_ids.any?
          @db[:entity_mentions]
            .join(:entities, id: :entity_id)
            .where(Sequel[:entity_mentions][:entry_id] => entry_ids,
              Sequel[:entities][:type] => "student")
            .group_and_count(Sequel[:entities][:name])
            .order(Sequel.desc(:count))
            .limit(8)
            .all
            .map { |r| [r[:name], r[:count]] }
        else
          []
        end

        # 누적 곡선 — 시간 구간별 누적 (week 단위)
        first_date = dates.first
        weeks = dates.map { |d| ((d - first_date) / 7).to_i }
        cumulative = weeks.each_with_index.map { |w, i| {week: w, cumulative: i + 1} }

        {
          total: rows.size,
          dates: dates,
          intervals: intervals,
          avg_interval: avg_interval,
          max_interval: max_interval,
          min_interval: min_interval,
          days_since_last: days_since_last,
          status: status,
          mode_counts: mode_counts,
          category_counts: category_counts,
          cohort: cohort,
          cumulative: cumulative
        }
      end

      def synthesize_deterministic(keyword, rows, a, _since_t, _until_t)
        lines = []
        lines << "## 📈 진행 상태"
        lines << ""
        status_label = {active: "🟢 진행 중", dormant: "🟡 휴면 (#{DORMANT_AFTER_DAYS}일+)",
                        ended: "🔴 종료 (#{ENDED_AFTER_DAYS}일+)"}[a[:status]]
        lines << "- **#{status_label}**"
        lines << "- 마지막 차시: #{a[:dates].last} (경과 #{a[:days_since_last]}일)"
        lines << "- 첫 차시: #{a[:dates].first}"
        lines << "- 총 차시: **#{a[:total]}건**"
        lines << ""

        if a[:avg_interval]
          lines << "## ⏱ 페이스 분석"
          lines << ""
          lines << "- 평균 차시 간격: **#{a[:avg_interval]}일**"
          lines << "- 최단 간격: #{a[:min_interval]}일 / 최장 간격: **#{a[:max_interval]}일**"
          consistency = (a[:intervals].count { |i| (i - a[:avg_interval]).abs <= 3 }.to_f / a[:intervals].size * 100).round(1)
          lines << "- 일정 비율: **#{consistency}%** (평균 ±3일 안 차시 비율)"
          lines << ""
        end

        lines << "## 📚 학습 활동 분포"
        lines << ""
        lines << "**모드별**: " + a[:mode_counts].map { |m, n| "#{mode_icon(m)} #{n}" }.join(" · ")
        lines << ""
        if a[:category_counts].any?
          lines << "**카테고리**: " + a[:category_counts].map { |c, n| "#{c} #{n}" }.join(" · ")
          lines << ""
        end

        if a[:cohort].any?
          lines << "## 👥 학습 cohort (자주 등장한 학생, 상위 8)"
          lines << ""
          a[:cohort].each { |name, n| lines << "- **#{name}**: #{n}회" }
          lines << ""
        end

        lines << "## 📊 누적 차시 곡선 (주 단위)"
        lines << ""
        max_cum = a[:cumulative].last[:cumulative]
        a[:cumulative].each do |c|
          bar_len = ((c[:cumulative].to_f / max_cum) * 30).to_i
          lines << "  주 #{format("%2d", c[:week])}: #{"▌" * bar_len} #{c[:cumulative]}"
        end
        lines << ""

        lines << "## 📅 차시 timeline"
        lines << ""
        rows.each_with_index do |r, i|
          icon = mode_icon(r[:mode])
          cat = r[:category].to_s.empty? ? "" : " · #{r[:category]}"
          title = r[:title].to_s.empty? ? "(제목 없음)" : r[:title]
          lines << "- [#{i + 1}] #{r[:created_at].to_s[0, 10]} #{icon}#{cat} — #{title} [[#{r[:path]}]]"
        end
        lines << ""

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (차시 timeline + 페이스·활동 분포 통계)._"
        lines << "_'학생 학습 부진' 같은 단정 X — 페이스 평가·다음 단계 제안은 LLM 모드에서._"
        lines << "_각 통계는 *원자료* — 학습 계획 수립은 교사 본인 판단._"
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

      def synthesize_via_llm(keyword, rows, a, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(keyword, rows, a, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(keyword, rows, a, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 학습 진척 추이를 분석합니다.
          입력: 차시 timeline + 페이스 통계 + 활동 분포 + 학습 cohort.
          톤: 객관적·관찰. 학생 능력 단정 X. 학습 부진/우수 단정 X.
          본문에 없는 사실 만들기 금지.

          출력 마크다운 (모든 섹션 포함):
          ## 🎯 학습 페이스 평가
          - 평균 간격·일정 비율 기반 1~2 문장. "빠른/느린 페이스" 객관적 표현.

          ## 📚 활동 균형 분석
          - 수업/평가/회고 비율로 보이는 패턴.

          ## 👥 학습 cohort 패턴 (있다면)
          - 자주 등장한 학생들의 *역할 분포* — 단정 X.

          ## 💡 다음 차시 우선순위 제안
          - 1~3개. "검토해 보면 어떨까요" 톤.

          분량: 400~1200자.
        TXT
      end

      def llm_user_prompt(keyword, rows, a, since_t, until_t)
        timeline = rows.first(15).map.with_index { |r, i|
          icon = mode_icon(r[:mode])
          cat = r[:category].to_s.empty? ? "" : " · #{r[:category]}"
          "[#{i + 1}] #{r[:created_at].to_s[0, 10]} #{icon}#{cat}: #{(r[:title] || "(제목 없음)")[0, 50]}"
        }.join("\n")
        cohort_text = a[:cohort].map { |n, c| "#{n}(#{c})" }.join(", ")
        cat_text = a[:category_counts].map { |c, n| "#{c}(#{n})" }.join(", ")
        <<~TXT
          # 학습 키워드: #{keyword}
          # 기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}
          # 총 차시: #{a[:total]}건 / 진행 상태: #{a[:status]}

          # 페이스
          평균 간격 #{a[:avg_interval]}일 (최단 #{a[:min_interval]} / 최장 #{a[:max_interval]})

          # 활동 분포
          모드: #{a[:mode_counts].map { |m, n| "#{m}(#{n})" }.join(", ")}
          카테고리: #{cat_text.empty? ? "(없음)" : cat_text}

          # 학습 cohort
          #{cohort_text.empty? ? "(없음)" : cohort_text}

          # 차시 timeline (최대 15)
          #{timeline}
        TXT
      end

      def build_full_content(keyword, body, rows, a, since_t, until_t)
        fm = {
          "is_synth" => true,
          "synth_target" => "learning-progress:#{keyword}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => rows.size,
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_keyword" => keyword,
          "synth_status" => a[:status].to_s,
          "synth_avg_interval_days" => a[:avg_interval],
          "synth_days_since_last" => a[:days_since_last],
          "synth_model" => synth_model_label,
          "title" => "학습 진척 추이: #{keyword}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 학습 진척 추이 — #{keyword}\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target(keyword)
        @vault_dir.join(SYNTH_DIR, "#{keyword}.md")
      end
    end
  end
end
