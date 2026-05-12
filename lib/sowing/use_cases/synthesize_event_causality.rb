# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 사건 인과 추론 — 임의 사건 키워드 + before/after 통계 변화 (확장 합성기 #12).
    #
    # vs 기존 #3 ExtractTrainingApplications:
    #   - #3: 연수 노트 1건 → 후속 *키워드 매칭* 사례
    #   - #12: 임의 *사건 키워드* (예: "협동학습 도입") → before/after *통계 변화*
    #     (톤 신호어 / 학생 mention / 카테고리 분포 / 작성 빈도)
    #
    # ⚠ 자율 판단 0 / 인과 단정 거부 (ADR-013):
    #   - **상관 = 인과 아님**. 합성기는 *관찰된 변화* 만 표시.
    #   - "X 사건 후 Y 가 일어났다 = X 가 Y 의 원인" X
    #   - 사용자가 데이터 보고 본인이 *해석/검증*
    #
    # 입력:
    #   - event_keyword: 사건 키워드 (예: "협동학습 도입", "학부모 모임", "단원평가")
    #   - first_occurrence: 처음 등장 시점 자동 탐지 (또는 since 명시)
    #   - window_days: before/after 각 N일 (default 30)
    #
    # 결정적 출력:
    #   - 사건 timeline (event_keyword 매칭 entries)
    #   - **before/after 비교 표**:
    #     - 작성 빈도 (entries/주)
    #     - 톤 신호어 (긍정/부정 카운트)
    #     - 학생 mention 분포 (새로 등장 / 사라짐)
    #     - 카테고리 분포 변화
    #
    # LLM 옵트인 출력 4 섹션:
    #   - 관찰된 변화 (사실 기반, 단정 X)
    #   - 가능한 상관 패턴 (인과 단정 X)
    #   - 본문 명시 사건 (사용자가 원인 후보로 본문에 적은 것만)
    #   - 다음 검증 제안
    #
    # 저장 위치: vault/.sowing/synth/event-causality/{slug}.md
    class SynthesizeEventCausality
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/event-causality"
      DEFAULT_WINDOW_DAYS = 30
      MIN_TOTAL_ENTRIES = 5  # before+after 합계 최소
      MAX_ENTRIES = 1000

      POSITIVE = %w[
        잘됐 성공 좋았 활기 집중 흥미 참여 효과적 만족 보람 자발 적극 협력
        몰입 감동 뿌듯 행복 즐거 신기 멋지 사랑스러 기특 자랑스러
      ].freeze
      NEGATIVE = %w[
        어려웠 힘들 산만 부족 아쉬웠 실패 혼란 지루 소극적 시간\ 부족
        피곤 지친 무거 답답 막막 막혀 슬프 외로 우울 짜증 걱정 불안
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

      # @param event_keyword [String] 사건 키워드 (예: "협동학습")
      # @param window_days [Integer] before/after 각 N일 (default 30)
      # @param event_at [Time, String, nil] 사건 발생 시점 명시 (nil = event_keyword 첫 등장 자동)
      # @return [Result] Success(Pathname) | Failure(:invalid_keyword | :event_not_found | :no_entries)
      def call(event_keyword:, window_days: DEFAULT_WINDOW_DAYS, event_at: nil)
        return Failure(:invalid_keyword) if event_keyword.to_s.strip.empty?

        # event 자동 탐지 — title/body 첫 매칭
        event_t = parse_time(event_at) || find_first_event(event_keyword)
        return Failure(:event_not_found) if event_t.nil?

        before_t = event_t - window_days * 86_400
        after_t = event_t + window_days * 86_400

        before_rows = @db[:entries]
          .where { (created_at >= before_t.iso8601) & (created_at < event_t.iso8601) }
          .order(:created_at).all
        after_rows = @db[:entries]
          .where { (created_at > event_t.iso8601) & (created_at <= after_t.iso8601) }
          .order(:created_at).all
        # event 등장 timeline (title + body 모두 매칭, 상위 10)
        all_event_t = (find_all_events(event_keyword) || []).first(10)

        total = before_rows.size + after_rows.size
        return Failure(:no_entries) if total < MIN_TOTAL_ENTRIES
        return Failure(:too_many_entries) if total > MAX_ENTRIES

        analysis = compare_periods(before_rows, after_rows, window_days)

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(event_keyword, event_t, all_event_t, before_rows, after_rows, analysis, window_days)
          }
        else
          synthesize_deterministic(event_keyword, event_t, all_event_t, before_rows, after_rows, analysis, window_days)
        end

        target = vault_target(event_keyword)
        content = build_full_content(event_keyword, body, event_t, all_event_t,
          before_rows, after_rows, analysis, window_days)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      # event_keyword 처음 등장 entry 의 created_at.
      def find_first_event(keyword)
        rows = @db[:entries].order(:created_at).all
        rows.each do |r|
          return Time.parse(r[:created_at].to_s) if r[:title].to_s.include?(keyword)
          body = read_body(r[:path])
          return Time.parse(r[:created_at].to_s) if body.include?(keyword)
        end
        nil
      end

      # 모든 event 등장 시점 (timeline 표시용).
      def find_all_events(keyword)
        rows = @db[:entries].order(:created_at).all
        rows.select { |r|
          r[:title].to_s.include?(keyword) || read_body(r[:path]).include?(keyword)
        }.map { |r|
          {
            date: r[:created_at].to_s[0, 10],
            mode: r[:mode],
            title: r[:title].to_s.empty? ? "(제목 없음)" : r[:title],
            path: r[:path]
          }
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

      def compare_periods(before_rows, after_rows, window_days)
        before_text = before_rows.map { |r| read_body(r[:path]) }.join("\n")
        after_text = after_rows.map { |r| read_body(r[:path]) }.join("\n")

        # 작성 빈도 (entries / 주)
        weeks = window_days / 7.0
        before_per_week = (before_rows.size / weeks).round(2)
        after_per_week = (after_rows.size / weeks).round(2)

        # 톤 신호어
        before_pos = count_signal_words(before_text, POSITIVE)
        before_neg = count_signal_words(before_text, NEGATIVE)
        after_pos = count_signal_words(after_text, POSITIVE)
        after_neg = count_signal_words(after_text, NEGATIVE)

        # 학생 mention — entity_mentions ⨝ entities 활용
        before_students = student_mentions(before_rows.map { |r| r[:id] })
        after_students = student_mentions(after_rows.map { |r| r[:id] })
        new_students = after_students - before_students
        gone_students = before_students - after_students

        # 카테고리 분포
        before_cats = before_rows.map { |r| r[:category].to_s }.reject(&:empty?).tally
        after_cats = after_rows.map { |r| r[:category].to_s }.reject(&:empty?).tally
        new_cats = after_cats.keys - before_cats.keys

        {
          before: {
            count: before_rows.size,
            per_week: before_per_week,
            positive: before_pos,
            negative: before_neg,
            students: before_students.to_a.sort,
            categories: before_cats.sort_by { |_, n| -n }.first(5)
          },
          after: {
            count: after_rows.size,
            per_week: after_per_week,
            positive: after_pos,
            negative: after_neg,
            students: after_students.to_a.sort,
            categories: after_cats.sort_by { |_, n| -n }.first(5)
          },
          new_students: new_students.to_a.sort,
          gone_students: gone_students.to_a.sort,
          new_categories: new_cats.sort
        }
      end

      def student_mentions(entry_ids)
        return Set.new if entry_ids.empty?
        @db[:entity_mentions]
          .join(:entities, id: :entity_id)
          .where(Sequel[:entity_mentions][:entry_id] => entry_ids,
            Sequel[:entities][:type] => "student")
          .select_map(Sequel[:entities][:name])
          .to_set
      end

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

      def synthesize_deterministic(keyword, event_t, all_events, _before, _after, a, window_days)
        lines = []
        lines << "## 🎯 사건 정보"
        lines << ""
        lines << "- **사건 키워드**: `#{keyword}`"
        lines << "- **기준 시점**: #{event_t.to_s[0, 10]} (자동 탐지: 첫 등장)"
        lines << "- **window**: 전 #{window_days}일 ↔ 후 #{window_days}일"
        lines << "- **본문 등장 횟수**: #{all_events.size}회"
        lines << ""

        if all_events.size > 1
          lines << "### 사건 등장 timeline (상위 10)"
          lines << ""
          all_events.each_with_index do |e, i|
            lines << "- [#{i + 1}] #{e[:date]} #{mode_icon(e[:mode])} #{e[:title]} [[#{e[:path]}]]"
          end
          lines << ""
        end

        lines << "## 📊 Before vs After 비교"
        lines << ""
        lines << "| 지표 | Before (#{window_days}일) | After (#{window_days}일) | 변화 |"
        lines << "|------|----------|----------|------|"
        lines << "| 작성 entries | #{a[:before][:count]} | #{a[:after][:count]} | #{change_arrow(a[:before][:count], a[:after][:count])} |"
        lines << "| 주당 빈도 | #{a[:before][:per_week]} | #{a[:after][:per_week]} | #{change_arrow(a[:before][:per_week], a[:after][:per_week])} |"
        lines << "| 긍정 신호어 | #{a[:before][:positive]} | #{a[:after][:positive]} | #{change_arrow(a[:before][:positive], a[:after][:positive])} |"
        lines << "| 부정 신호어 | #{a[:before][:negative]} | #{a[:after][:negative]} | #{change_arrow(a[:before][:negative], a[:after][:negative])} |"
        lines << "| 학생 mention 수 | #{a[:before][:students].size} | #{a[:after][:students].size} | #{change_arrow(a[:before][:students].size, a[:after][:students].size)} |"
        lines << ""

        if a[:new_students].any?
          lines << "## 🆕 새로 등장한 학생 (Before 에 없던)"
          lines << ""
          a[:new_students].each { |s| lines << "- #{s}" }
          lines << ""
        end

        if a[:gone_students].any?
          lines << "## 🌑 등장 멈춘 학생 (Before 엔 있었지만 After 엔 없음)"
          lines << ""
          a[:gone_students].each { |s| lines << "- #{s}" }
          lines << ""
        end

        if a[:new_categories].any?
          lines << "## 🆕 새 카테고리 등장 (After)"
          lines << ""
          a[:new_categories].each { |c| lines << "- #{c}" }
          lines << ""
        end

        lines << "## 📚 카테고리 분포"
        lines << ""
        lines << "**Before** (top 5): " + (a[:before][:categories].any? ? a[:before][:categories].map { |c, n| "#{c} #{n}" }.join(" · ") : "_없음_")
        lines << ""
        lines << "**After** (top 5): " + (a[:after][:categories].any? ? a[:after][:categories].map { |c, n| "#{c} #{n}" }.join(" · ") : "_없음_")
        lines << ""

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (before/after 통계 비교)._"
        lines << "_⚠ **상관 = 인과 아님**. 사건 후 변화가 *관찰* 됐어도 그것이 사건 *때문* 인지는 사용자 판단._"
        lines << "_의미 단위 인과 추정·검증 제안은 LLM 모드에서. 그것조차 *후보* 일 뿐._"
        lines.join("\n")
      end

      def change_arrow(before, after)
        return "—" if before == after
        diff = after - before
        sign = (diff > 0) ? "↑" : "↓"
        "#{sign} #{diff.abs}"
      end

      def mode_icon(mode)
        case mode.to_s
        when "memo" then "💭"
        when "note" then "📝"
        when "record" then "📖"
        else "·"
        end
      end

      def synthesize_via_llm(keyword, event_t, all_events, before, after, a, window_days)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(keyword, event_t, all_events, before, after, a, window_days)
        ).to_s.strip
      rescue
        synthesize_deterministic(keyword, event_t, all_events, before, after, a, window_days)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 사건의 *상관 패턴* 을 검토합니다.
          입력: before/after 통계 비교 + 사건 timeline.
          톤: 객관적·신중. **인과 단정 절대 금지** — "X 가 Y 의 원인이다" X.
          본문에 없는 사실 만들기 금지. 후보로만 표현.

          출력 마크다운 (모든 섹션 포함):
          ## 📊 관찰된 변화 (사실)
          - before/after 통계 1~2 문장. 단정 X.

          ## 🤔 가능한 상관 패턴 (해석 후보)
          - "~가 ~과 함께 변했다" 같은 *상관* 표현. 인과 X.
          - 강한 단정 거부 — "원인일 가능성", "관련일 수도" 톤.

          ## 📝 본문에 명시된 사건 (있다면)
          - 사용자가 본문에 *직접 적은* 인과 가설만 인용. 합성기 추정 X.

          ## 💡 다음 검증 제안
          - 추가 데이터·관찰 제안 1~3개. "~을 더 보면 명확해질 것 같아요" 톤.

          분량: 400~1200자.
        TXT
      end

      def llm_user_prompt(keyword, event_t, all_events, _before, _after, a, window_days)
        cat_b = a[:before][:categories].map { |c, n| "#{c}(#{n})" }.join(", ")
        cat_a = a[:after][:categories].map { |c, n| "#{c}(#{n})" }.join(", ")
        <<~TXT
          # 사건 키워드: #{keyword}
          # 기준 시점: #{event_t.to_s[0, 10]} (자동 탐지)
          # window: 전후 #{window_days}일

          # 사건 등장 timeline (#{all_events.size}회)
          #{all_events.first(10).map { |e| "- #{e[:date]} #{e[:title]}" }.join("\n")}

          # Before 통계
          - entries: #{a[:before][:count]}, 주당 #{a[:before][:per_week]}
          - 긍정 #{a[:before][:positive]} / 부정 #{a[:before][:negative]}
          - 학생: #{a[:before][:students].first(8).join(", ")}
          - 카테고리: #{cat_b.empty? ? "(없음)" : cat_b}

          # After 통계
          - entries: #{a[:after][:count]}, 주당 #{a[:after][:per_week]}
          - 긍정 #{a[:after][:positive]} / 부정 #{a[:after][:negative]}
          - 학생: #{a[:after][:students].first(8).join(", ")}
          - 카테고리: #{cat_a.empty? ? "(없음)" : cat_a}

          # 변화
          - 새로 등장 학생: #{a[:new_students].first(8).join(", ")}
          - 등장 멈춘 학생: #{a[:gone_students].first(8).join(", ")}
          - 새 카테고리: #{a[:new_categories].join(", ")}
        TXT
      end

      def build_full_content(keyword, body, event_t, all_events, before, after, a, window_days)
        fm = {
          "is_synth" => true,
          "synth_target" => "event-causality:#{keyword}",
          "synth_at" => @clock.now.iso8601,
          "synth_event_keyword" => keyword,
          "synth_event_at" => event_t.iso8601,
          "synth_event_occurrences" => all_events.size,
          "synth_window_days" => window_days,
          "synth_before_count" => before.size,
          "synth_after_count" => after.size,
          "synth_new_student_count" => a[:new_students].size,
          "synth_model" => synth_model_label,
          "title" => "사건 인과 추론: #{keyword}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 사건 인과 추론 — #{keyword}\n\n#{body}\n"
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
