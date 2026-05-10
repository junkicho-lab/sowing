# frozen_string_literal: true

require "date"
require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 주간 회고 합성 (확장 합성기 #4).
    #
    # 학기 회고(W21-T01)는 호흡이 너무 길고 학생 디제스트는 너무 짧음.
    # 그 사이의 *한 주 단위* 자동 정리. 매주 일요일 트리거 가능.
    #
    # 입력: 최근 7일 entries (default = 이번 ISO 주, 월요일 ~ 일요일).
    # 출력 섹션:
    #   - 결정적: 모드별 카운트 + 일별 빈도 + top 학생 + 미완료 task (`- [ ]`)
    #   - LLM: 이번 주 흐름 / 작은 발견 / 미해결 / 다음 주 우선순위
    #
    # 저장: vault/.sowing/synth/weekly/{YYYY-WW}.md (ISO 주 라벨)
    #
    # 자율 판단 0:
    #   - "이번 주 잘했다/못했다" 단정 X
    #   - 통계 + 인용 + 미완료 task 만 객관적으로
    class SynthesizeWeeklyReview
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/weekly"
      MIN_ENTRIES = 1   # 1건만 있어도 회고 가치 있음 (적게 쓴 주의 알림)
      MAX_ENTRIES = 200
      EXCERPT_LIMIT = 160
      TOP_STUDENT_N = 5

      # 미완료 task 패턴 — 본문 안의 `- [ ]` 또는 `* [ ]` 체크박스.
      INCOMPLETE_TASK_RE = /^\s*[-*]\s*\[\s*\]\s*(.+)$/

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

      # @param week_label [String, nil] ISO 주 라벨 (예: "2026-W19"). nil = 자동 (clock.now 기준)
      # @param since [Time, String, nil] 시작 시점. nil + week_label 도 nil 이면 자동
      # @param until_time [Time, String, nil] 종료 시점.
      # @return [Result] Success(Pathname) | Failure(:no_entries | :too_many_entries)
      def call(week_label: nil, since: nil, until_time: nil)
        if week_label.nil? && since.nil? && until_time.nil?
          # 자동 — 이번 ISO 주 (월요일 00:00 ~ 일요일 23:59)
          now = @clock.now
          since_t = monday_of_iso_week(now)
          until_t = since_t + 7 * 86_400 - 1
          week_label = format_iso_week(now)
        else
          until_t = parse_time(until_time) || @clock.now
          since_t = parse_time(since) || (until_t - 7 * 86_400)
          week_label ||= format_iso_week(since_t)
        end

        entry_rows = @db[:entries]
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .order(:created_at)
          .all
        return Failure(:no_entries) if entry_rows.size < MIN_ENTRIES
        return Failure(:too_many_entries) if entry_rows.size > MAX_ENTRIES

        stats = compute_stats(entry_rows, since_t, until_t)
        tasks = collect_incomplete_tasks(entry_rows)

        body = if @llm_backend
          Infrastructure::AuditLog.with_actor("agent") {
            synthesize_via_llm(week_label, stats, tasks, entry_rows, since_t, until_t)
          }
        else
          synthesize_deterministic(week_label, stats, tasks, since_t, until_t)
        end

        target = vault_target(week_label)
        content = build_full_content(week_label, body, stats, tasks, since_t, until_t)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      def monday_of_iso_week(time)
        date = time.to_date
        # ISO 주: 월요일=1, 일요일=7
        offset = date.cwday - 1
        monday = date - offset
        Time.new(monday.year, monday.month, monday.day, 0, 0, 0, time.utc_offset)
      end

      def format_iso_week(time)
        date = time.to_date
        # ISO 주: cweek (1~52/53), cwyear (ISO year)
        format("%04d-W%02d", date.cwyear, date.cweek)
      end

      def compute_stats(entry_rows, since_t, until_t)
        mode_counts = entry_rows.group_by { |r| r[:mode] }.transform_values(&:count)
        category_counts = entry_rows
          .map { |r| r[:category].to_s }
          .reject(&:empty?)
          .tally

        # 일별 빈도 — created_at[0,10] 으로 그룹
        daily_counts = entry_rows
          .group_by { |r| r[:created_at].to_s[0, 10] }
          .transform_values(&:count)

        # 이번 주 자주 등장 학생 — entity_mentions ⨝ entities
        entry_ids = entry_rows.map { |r| r[:id] }
        student_counts = if entry_ids.any?
          @db[:entity_mentions]
            .join(:entities, id: :entity_id)
            .where(Sequel[:entity_mentions][:entry_id] => entry_ids, Sequel[:entities][:type] => "student")
            .group_and_count(Sequel[:entities][:name])
            .order(Sequel.desc(:count))
            .limit(TOP_STUDENT_N)
            .all
            .map { |r| [r[:name], r[:count]] }
        else
          []
        end

        {
          since: since_t,
          until: until_t,
          total: entry_rows.size,
          mode_counts: mode_counts,
          category_counts: category_counts,
          daily_counts: daily_counts,
          student_counts: student_counts
        }
      end

      # 본문에서 `- [ ]` 패턴 추출 — 이번 주 미완료 task 모음.
      def collect_incomplete_tasks(entry_rows)
        tasks = []
        entry_rows.each do |row|
          body = read_body(row[:path])
          next if body.empty?
          body.each_line do |line|
            m = line.match(INCOMPLETE_TASK_RE)
            next unless m
            tasks << {
              path: row[:path],
              date: row[:created_at].to_s[0, 10],
              text: m[1].strip
            }
          end
        end
        tasks
      end

      def read_body(rel_path)
        abs = @vault_dir.join(rel_path)
        return "" unless abs.exist?
        parsed = @parser.call(abs.read)
        parsed.content.to_s
      rescue
        ""
      end

      def synthesize_deterministic(_week_label, stats, tasks, since_t, until_t)
        lines = []
        lines << "## 📅 이번 주 요약"
        lines << ""
        lines << "기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}, 총 #{stats[:total]}건"
        lines << ""
        lines << "**모드별**: " + stats[:mode_counts].map { |m, n| "#{mode_label(m)} #{n}" }.join(" · ")
        lines << ""

        if stats[:category_counts].any?
          lines << "**카테고리**: " + stats[:category_counts].sort_by { |_, n| -n }.first(5).map { |c, n| "#{c} #{n}" }.join(" · ")
          lines << ""
        end

        lines << "## 📊 일별 작성 빈도"
        lines << ""
        if stats[:daily_counts].any?
          stats[:daily_counts].sort.each do |date, count|
            bar = "▌" * count
            lines << "- #{date} (#{korean_weekday(date)}): #{bar} #{count}건"
          end
        else
          lines << "_작성 없음_"
        end
        lines << ""

        lines << "## 👥 자주 등장한 학생 (상위 #{TOP_STUDENT_N})"
        lines << ""
        if stats[:student_counts].any?
          stats[:student_counts].each do |name, n|
            lines << "- **#{name}**: #{n}회 언급"
          end
        else
          lines << "_학생 언급 없음 (또는 entity 인덱스 없음)._"
        end
        lines << ""

        lines << "## ☐ 미완료 task (#{tasks.size}건)"
        lines << ""
        if tasks.any?
          tasks.first(20).each do |t|
            lines << "- [ ] #{t[:text]}"
            lines << "  · #{t[:date]} [[#{t[:path]}]]"
          end
          if tasks.size > 20
            lines << "- _그 외 #{tasks.size - 20}건._"
          end
        else
          lines << "_본문에 `- [ ]` 패턴 없음._"
        end
        lines << ""

        lines << "---"
        lines << ""
        lines << "_본 회고는 결정적 합성 (통계 + task 추출). 흐름·발견·다음 주 우선순위 분석은 LLM 모드에서._"
        lines << "_'잘했다/못했다' 단정 X — 객관 통계와 인용만 제공._"
        lines.join("\n")
      end

      def korean_weekday(date_str)
        days = %w[일 월 화 수 목 금 토]
        d = Date.parse(date_str.to_s)
        days[d.wday]
      rescue
        ""
      end

      def mode_label(mode)
        case mode.to_s
        when "memo" then "💭"
        when "note" then "📝"
        when "record" then "📖"
        else "·"
        end
      end

      def synthesize_via_llm(week_label, stats, tasks, entry_rows, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(week_label, stats, tasks, entry_rows, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(week_label, stats, tasks, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 한 주 회고를 작성합니다.
          입력: 이번 주 통계 + 미완료 task + entry 인용 일부.
          톤: 객관적·격려적. 평가·단정 X. 본문에 없는 사실 만들기 금지.

          출력 마크다운 (모든 섹션 포함):
          ## 🌊 이번 주 흐름
          - 1~2 문장. 통계 기반.

          ## 💡 작은 발견
          - 인용 [#] + 1~2 문장 관찰

          ## ☐ 미해결 / 미완료
          - task 목록 + 우선순위 제안 (강요 X)

          ## 🎯 다음 주 우선순위
          - 1~3개. "~해보세요" X, "~을 검토해 보면 어떨까요" 톤

          분량: 300~800자.
        TXT
      end

      def llm_user_prompt(week_label, stats, tasks, entry_rows, since_t, until_t)
        sample = entry_rows.first(15).map { |r|
          excerpt = read_body(r[:path]).split(/[.!?。\n]+/).first.to_s.strip
          excerpt = (excerpt.length > EXCERPT_LIMIT) ? "#{excerpt[0, EXCERPT_LIMIT]}…" : excerpt
          "[#{r[:created_at].to_s[0, 10]}] #{mode_label(r[:mode])}: #{excerpt}"
        }.join("\n")
        student_text = stats[:student_counts].map { |n, c| "#{n}(#{c}회)" }.join(", ")
        task_text = tasks.first(15).map { |t| "- #{t[:text]}" }.join("\n")
        <<~TXT
          # 주: #{week_label} (#{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]})
          # 총 #{stats[:total]}건, 모드별: #{stats[:mode_counts].map { |m, n| "#{m} #{n}" }.join(", ")}
          # 자주 등장 학생: #{student_text.empty? ? "(없음)" : student_text}

          # entries 인용 (최대 15건)
          #{sample}

          # 미완료 task (#{tasks.size}건)
          #{task_text.empty? ? "(없음)" : task_text}
        TXT
      end

      def build_full_content(week_label, body, stats, tasks, since_t, until_t)
        fm = {
          "is_synth" => true,
          "synth_target" => "week:#{week_label}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => stats[:total],
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_incomplete_task_count" => tasks.size,
          "synth_model" => synth_model_label,
          "title" => "주간 회고: #{week_label}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 주간 회고: #{week_label}\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target(week_label)
        @vault_dir.join(SYNTH_DIR, "#{week_label}.md")
      end
    end
  end
end
