# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 계절성 패턴 합성 — 같은 월(month)의 여러 연도 entries 비교 (확장 합성기 #8).
    #
    # "매년 이 시기에 비슷한 어려움이 반복된다" 발견. 연차 1년 후부터 폭발적 가치 —
    # 지금 인프라만 깔아두면 나중에 자동으로 의미가 쌓임 (long-term play).
    #
    # 입력: 월(MM) 1~12 + 연도 무관 모든 entries
    # 출력:
    #   - 결정적: 연도별 그룹 + 작년/재작년/올해 timeline 비교 + 모드·카테고리 분포
    #   - LLM: 매년 반복되는 패턴 / 매년 다른 점 / 올해 시도해볼 만한 것
    #
    # 저장: vault/.sowing/synth/seasonal/{MM}.md (월당 1 파일, 매년 갱신)
    #
    # 한계 인정 (자율 판단 0):
    #   - 1년 미만 사용 시 비교할 데이터 없음 → 안내 문구
    #   - "이 시기에 항상 ~한다" 단정 X — *반복으로 보이는 후보* 만
    #   - LLM 모드 도 본문에 없는 사실 만들기 금지
    class SynthesizeSeasonalPattern
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/seasonal"
      MIN_ENTRIES = 3        # 한 월 안 최소 (1년 분량이라도)
      MAX_ENTRIES = 1000     # 안전 가드
      EXCERPT_LIMIT = 160
      MIN_YEARS_FOR_PATTERN = 2  # 패턴 발견은 2년치 이상 필요

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

      # @param month [Integer] 1~12. nil 이면 clock.now 의 이번 달
      # @return [Result] Success(Pathname) | Failure(:invalid_month | :no_entries | :too_many_entries)
      def call(month: nil)
        m = month || @clock.now.month
        return Failure(:invalid_month) unless (1..12).cover?(m.to_i)
        m = m.to_i

        # 모든 entries 중 created_at 의 month 가 m 인 것
        # SQLite strftime 함수 활용 — created_at 이 ISO 문자열이라 SUBSTR 로 충분
        all_rows = @db[:entries]
          .where(Sequel.lit("CAST(SUBSTR(created_at, 6, 2) AS INTEGER) = ?", m))
          .order(:created_at)
          .all
        return Failure(:no_entries) if all_rows.size < MIN_ENTRIES
        return Failure(:too_many_entries) if all_rows.size > MAX_ENTRIES

        # 연도별 그룹
        by_year = all_rows.group_by { |r| r[:created_at].to_s[0, 4].to_i }.sort
        years = by_year.map(&:first)
        current_year = @clock.now.year

        items = all_rows.map { |row| build_item(row) }

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(m, by_year, years, current_year, items)
          }
        else
          synthesize_deterministic(m, by_year, years, current_year, items)
        end

        target = vault_target(m)
        content = build_full_content(m, body, by_year, years, current_year, items)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def build_item(row)
        body = read_body(row[:path])
        first_sentence = body.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?).first.to_s
        excerpt = (first_sentence.length > EXCERPT_LIMIT) ? "#{first_sentence[0, EXCERPT_LIMIT]}…" : first_sentence
        {
          id: row[:id],
          path: row[:path],
          mode: row[:mode],
          title: row[:title],
          category: row[:category],
          created_at: row[:created_at],
          year: row[:created_at].to_s[0, 4].to_i,
          excerpt: excerpt
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

      def synthesize_deterministic(month, by_year, years, current_year, items)
        lines = []
        month_label = format("%02d월", month)
        lines << "## 🍂 #{month_label} 계절성 패턴"
        lines << ""

        lines << if years.size < MIN_YEARS_FOR_PATTERN
          "_연차가 #{years.size}년뿐입니다 (#{years.first}). 계절성 패턴 발견은 #{MIN_YEARS_FOR_PATTERN}년 이상 누적 후 의미가 생깁니다 — 지금은 *씨를 뿌리는 단계*._"
        else
          "비교 가능 연차: #{years.join(", ")} (#{years.size}년)"
        end
        lines << ""

        # 연도별 카운트
        lines << "**연도별**: " + by_year.map { |y, rows| "#{y} #{rows.size}건" }.join(" · ")
        lines << ""

        # 카테고리 분포 (전체)
        cat_counts = items.map { |i| i[:category].to_s }.reject(&:empty?).tally.sort_by { |_, n| -n }
        if cat_counts.any?
          lines << "**자주 다룬 카테고리**: " + cat_counts.first(5).map { |c, n| "#{c} #{n}" }.join(" · ")
          lines << ""
        end

        # 연도별 timeline
        lines << "## 📋 연도별 entries (#{items.size}건 총합)"
        lines << ""
        by_year.each do |year, rows|
          year_marker = (year == current_year) ? " 🎯 (올해)" : ""
          lines << "### #{year}년#{year_marker} — #{rows.size}건"
          lines << ""
          rows.first(5).each do |row|
            title = row[:title].to_s.empty? ? "(제목 없음)" : row[:title]
            cat = row[:category].to_s.empty? ? "" : " · #{row[:category]}"
            lines << "- #{row[:created_at].to_s[0, 10]} #{mode_icon(row[:mode])}#{cat} [[#{row[:path]}]] — #{title}"
          end
          if rows.size > 5
            lines << "- _그 외 #{rows.size - 5}건._"
          end
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (월별 그룹 + 연도 비교)._"
        lines << if years.size >= MIN_YEARS_FOR_PATTERN
          "_매년 반복 패턴 / 매년 다른 점 / 올해 시도할 만한 것 분석은 LLM 모드에서._"
        else
          "_연차가 더 쌓이면 LLM 모드가 의미 있어집니다 — 지금은 통계만._"
        end
        lines << "_'이 시기에 항상 ~한다' 단정 X — *반복으로 보이는 후보* 일 뿐._"
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

      def synthesize_via_llm(month, by_year, years, current_year, items)
        @llm_backend.chat(
          system: llm_system_prompt(years.size),
          user: llm_user_prompt(month, by_year, years, current_year, items)
        ).to_s.strip
      rescue
        synthesize_deterministic(month, by_year, years, current_year, items)
      end

      def llm_system_prompt(years_count)
        if years_count < MIN_YEARS_FOR_PATTERN
          <<~TXT
            한국 초등 교사의 이번 달 entries 만 있습니다 (연차 #{years_count}년).
            계절성 비교는 못 하지만, 이번 달의 흐름·핵심 사건·다음 달 준비는 정리 가능합니다.
            톤: 객관적·관찰. 단정 X.

            출력:
            ## 🌱 이번 달 흐름
            ## 💡 핵심 사건 / 발견
            ## 🎯 다음 달 준비

            분량: 300~700자.
          TXT
        else
          <<~TXT
            한국 초등 교사의 같은 달 (#{years_count}년치) entries 비교.
            톤: 발견·통찰. "항상 ~한다" 단정 X. 본문에 없는 사실 만들기 금지.

            출력 마크다운:
            ## 🔁 매년 반복되는 패턴 (관찰)
            - 인용 [#] + "N년 모두 X" 형식

            ## 🌊 매년 다른 점
            - 연도 차이 + 인용

            ## 🎯 올해 시도해 볼 만한 것 (제안)
            - 본문 기반 1~3개. "~해보세요" X, "~을 검토해 보면 어떨까요" 톤

            분량: 400~1200자.
          TXT
        end
      end

      def llm_user_prompt(month, by_year, years, current_year, items)
        timeline = items.first(40).map.with_index { |item, i|
          year_marker = (item[:year] == current_year) ? "(올해)" : ""
          cat = item[:category].to_s.empty? ? "" : " · #{item[:category]}"
          "[#{i + 1}] #{item[:created_at].to_s[0, 10]} #{year_marker} #{mode_icon(item[:mode])}#{cat}: #{item[:excerpt]}"
        }.join("\n")
        <<~TXT
          # 월: #{format("%02d", month)}월
          # 연차: #{years.join(", ")} (#{years.size}년)
          # 연도별 카운트: #{by_year.map { |y, r| "#{y}: #{r.size}건" }.join(", ")}

          # entries (시간순, 최대 40건)
          #{timeline}
        TXT
      end

      def build_full_content(month, body, by_year, years, current_year, items)
        fm = {
          "is_synth" => true,
          "synth_target" => "season:#{format("%02d", month)}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => items.size,
          "synth_month" => month,
          "synth_years" => years,
          "synth_year_counts" => by_year.to_h { |y, rows| [y, rows.size] },
          "synth_current_year" => current_year,
          "synth_pattern_eligible" => years.size >= MIN_YEARS_FOR_PATTERN,
          "synth_model" => synth_model_label,
          "title" => "계절성 패턴: #{format("%02d", month)}월"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 계절성 패턴: #{format("%02d", month)}월\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target(month)
        @vault_dir.join(SYNTH_DIR, "#{format("%02d", month)}.md")
      end
    end
  end
end
