# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 수업 시리즈 추적 (확장 합성기 #6).
    #
    # 한 단원 (예: "분수") 이 5~10차시에 걸쳐 진행되는데, 차시별 entries 가
    # 흩어져 있어 *전체 흐름* 을 한 화면에 못 봄. 키워드 기반으로 모음 + timeline.
    #
    # 입력: 키워드 (예: "분수") + 시간 window (default 6개월)
    #   - title 또는 body 에 키워드 포함하는 entries 모두 매칭
    #   - 시간순 timeline
    #
    # 출력:
    #   - 결정적: 차시별 timeline + mode 아이콘 + 단원 종료 자동 감지
    #     (마지막 entry 후 N일 — default 14일 — 경과 시 "종료된 시리즈")
    #   - LLM: 단원 흐름 요약 + 학생 반응 변화 + 다음 단원 준비 제안
    #
    # 저장: vault/.sowing/synth/lesson-series/{slug}.md
    #   - slug = 키워드 자체 (한국어 가능, NFC 정규화)
    #
    # 자율 판단 0:
    #   - "이 단원이 잘됐다" 단정 X
    #   - 차시별 인용 + 시간 흐름만 객관적으로
    class SynthesizeLessonSeries
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/lesson-series"
      DEFAULT_WINDOW_DAYS = 180  # 6개월
      MIN_ENTRIES = 2
      MAX_ENTRIES = 200
      EXCERPT_LIMIT = 200
      ENDED_AFTER_DAYS = 14      # 마지막 entry 후 14일 경과 → "종료된 시리즈"

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

      # @param keyword [String] 단원·주제 키워드 (예: "분수", "협동학습")
      # @param since [Time, String, nil] 시작 시점. nil = 6개월 전
      # @param until_time [Time, String, nil] 종료 시점. nil = now
      # @return [Result] Success(Pathname) | Failure(:no_entries | :too_many_entries)
      def call(keyword:, since: nil, until_time: nil)
        return Failure(:invalid_keyword) if keyword.to_s.strip.empty?

        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        # title 또는 body 키워드 매칭. body 매칭은 vault 파일 직접 읽음 (인덱스에 본문 없음).
        candidate_rows = @db[:entries]
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .order(:created_at)
          .all

        matched = candidate_rows.select { |row|
          title_match = row[:title].to_s.include?(keyword)
          next true if title_match
          # body 검색 (vault 파일)
          body = read_body(row[:path])
          body.include?(keyword)
        }

        return Failure(:no_entries) if matched.size < MIN_ENTRIES
        return Failure(:too_many_entries) if matched.size > MAX_ENTRIES

        items = matched.map { |row| build_item(row, keyword) }
        status = compute_status(items)

        body = if @llm_backend
          Infrastructure::AuditLog.with_actor("agent") {
            synthesize_via_llm(keyword, items, status, since_t, until_t)
          }
        else
          synthesize_deterministic(keyword, items, status, since_t, until_t)
        end

        target = vault_target(keyword)
        content = build_full_content(keyword, body, items, status, since_t, until_t)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      def build_item(row, keyword)
        body = read_body(row[:path])
        excerpt = relevant_excerpt(body, keyword)
        {
          id: row[:id],
          path: row[:path],
          mode: row[:mode],
          title: row[:title],
          category: row[:category],
          created_at: row[:created_at],
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

      def relevant_excerpt(body, keyword)
        sentences = body.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?)
        match = sentences.find { |s| s.include?(keyword) } || sentences.first || ""
        (match.length > EXCERPT_LIMIT) ? "#{match[0, EXCERPT_LIMIT]}…" : match
      end

      # 단원 종료 자동 감지 — 마지막 entry 후 ENDED_AFTER_DAYS 일 경과 시 :ended.
      def compute_status(items)
        last_date = Time.parse(items.last[:created_at].to_s)
        days_since = ((@clock.now - last_date) / 86_400).to_i
        first_date = Time.parse(items.first[:created_at].to_s)
        duration_days = ((last_date - first_date) / 86_400).to_i
        {
          status: (days_since >= ENDED_AFTER_DAYS) ? :ended : :active,
          first_date: first_date,
          last_date: last_date,
          duration_days: duration_days,
          days_since_last: days_since
        }
      end

      def synthesize_deterministic(_keyword, items, status, _since_t, _until_t)
        lines = []

        status_label = (status[:status] == :ended) ? "✅ 종료된 시리즈" : "🟢 진행 중인 시리즈"
        lines << "## #{status_label}"
        lines << ""
        lines << "기간: #{status[:first_date].to_s[0, 10]} ~ #{status[:last_date].to_s[0, 10]} (#{status[:duration_days]}일 진행)"
        lines << if status[:status] == :ended
          "마지막 entry 후 #{status[:days_since_last]}일 경과 (#{ENDED_AFTER_DAYS}일 기준)."
        else
          "마지막 entry 후 #{status[:days_since_last]}일 — 진행 중일 가능성."
        end
        lines << ""

        # mode 분포
        mode_counts = items.group_by { |i| i[:mode] }.transform_values(&:count)
        lines << "**모드별**: " + mode_counts.map { |m, n| "#{mode_icon(m)} #{n}" }.join(" · ")
        lines << ""

        lines << "## 📋 차시별 timeline (#{items.size}건, 시간순)"
        lines << ""
        items.each_with_index do |item, i|
          title = item[:title].to_s.empty? ? "(제목 없음)" : item[:title]
          cat = item[:category].to_s.empty? ? "" : " · #{item[:category]}"
          lines << "### [#{i + 1}] #{item[:created_at].to_s[0, 10]} #{mode_icon(item[:mode])}#{cat} — #{title}"
          lines << ""
          lines << "> #{item[:excerpt]}"
          lines << ""
          lines << "출처: [[#{item[:path]}]]"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (키워드 매칭 + 시간순 timeline + 종료 자동 감지)._"
        lines << "_단원 흐름·학생 반응 변화·다음 단원 준비 분석은 LLM 모드에서. 차시 단정 X — 인용 모음._"
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

      def synthesize_via_llm(keyword, items, status, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(keyword, items, status, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(keyword, items, status, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 한 단원/주제의 차시별 흐름을 정리합니다.
          입력: 시간순 entries 인용 + 단원 status (진행 중 / 종료).
          톤: 객관적·관찰. 단정·평가 X. 본문에 없는 사실 만들기 금지.

          출력 마크다운 (모든 섹션 포함):
          ## 🎒 단원 흐름
          - 시간순 흐름 1~3 문장. 통계·인용 기반.

          ## 👥 학생 반응 변화 (관찰)
          - 인용 [#] + 차시별 변화 표시

          ## 🌱 잘된 차시 / 아쉬웠던 차시 (관찰)
          - 인용 [#] (단정 X)

          ## 📚 다음 단원 준비 (제안)
          - 본문 기반 1~3개. "~해보세요" X, "~을 검토해 보면 어떨까요" 톤

          분량: 400~1200자.
        TXT
      end

      def llm_user_prompt(keyword, items, status, since_t, until_t)
        list = items.map.with_index { |row, i|
          cat = row[:category].to_s.empty? ? "" : " · #{row[:category]}"
          title = row[:title].to_s.empty? ? "" : " — #{row[:title]}"
          "[#{i + 1}] #{row[:created_at].to_s[0, 10]} #{mode_icon(row[:mode])}#{cat}#{title}: #{row[:excerpt]}"
        }.join("\n")
        <<~TXT
          # 단원/주제: #{keyword}
          # 기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}
          # 상태: #{status[:status]} (#{status[:duration_days]}일 진행, 마지막 entry 후 #{status[:days_since_last]}일)

          # 차시별 인용 (#{items.size}건)
          #{list}
        TXT
      end

      def build_full_content(keyword, body, items, status, since_t, until_t)
        fm = {
          "is_synth" => true,
          "synth_target" => "series:#{keyword}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => items.size,
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_keyword" => keyword,
          "synth_first_date" => status[:first_date].iso8601,
          "synth_last_date" => status[:last_date].iso8601,
          "synth_status" => status[:status].to_s,
          "synth_duration_days" => status[:duration_days],
          "synth_model" => synth_model_label,
          "title" => "수업 시리즈: #{keyword}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 수업 시리즈: #{keyword}\n\n#{body}\n"
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
