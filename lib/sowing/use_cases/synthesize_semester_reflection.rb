# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 학기 단위 회고 합성 — 100~500건 entries 의 누적 패턴을 마크다운 회고로 (W21-T01).
    #
    # ADR-013 의 Phase 12 요건 (Phase 11 합성기 패턴 그대로 확장):
    #   - 결정적 fallback (timeline + 통계 + top-N, LLM 미사용 모드 1급)
    #   - LLM 옵트인 (변화의 순간·잘된·아쉬웠던 분석은 LLM 모드에서만)
    #   - 합성 산출물은 frontmatter `is_synth: true` + `synth_target: "semester:{label}"` 표시
    #   - audit log actor=agent 자동 마킹 (`with_actor` 블록)
    #   - 청크 분할 — 월 단위로 entries 그룹핑, 청크별 LLM 요청 → 종합 prompt
    #     (long-context 한계 우회. backend 가 작은 context window 라도 동작)
    #
    # 저장 위치: vault/.sowing/synth/reflections/{semester_label}.md
    #   - 마크다운 SoT, 옵시디언 직접 열람 가능
    #   - .sowing/ prefix → watcher 인덱싱 회피, 사용자 검토 후 일반 위치로 이동 가능
    #   - semester_label 예: "2026-1" (3~7월) / "2026-2" (9~다음해 1월) / 임의 라벨
    #
    # 멱등: 같은 semester_label 재호출 → 기존 파일 atomic 덮어쓰기 (synth_at 갱신).
    #
    # 입력 범위 디자인:
    #   - `since:` / `until:` 명시 시 그 범위 (검증 가능, 결정적)
    #   - 둘 다 미지정 시 default = 최근 6개월 (학기 분량)
    #   - 너무 적으면 (`Failure(:no_entries)`) — 회고 가치 없음
    #   - 너무 많으면 (>1000) — `Failure(:too_many_entries)` (안전 가드. 사용자가 명시
    #     좁힌 범위 다시 호출하도록)
    class SynthesizeSemesterReflection
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/reflections"
      DEFAULT_WINDOW_DAYS = 180  # 약 6개월 — 한국 학기 분량
      MIN_ENTRIES = 5            # 최소: 회고 가치 있는 누적량
      MAX_ENTRIES = 1000         # 최대: 안전 가드 (token 폭발 방지)
      EXCERPT_LIMIT = 160        # 인용 발췌 길이
      TOP_STUDENT_N = 5          # 자주 등장 학생 상위 N
      TOP_CATEGORY_N = 5         # 자주 다룬 카테고리 상위 N

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

      # @param semester_label [String] 회고 식별 라벨 (예: "2026-1")
      # @param since [Time, String, nil] 시작 시점 (포함). nil 이면 until 또는 now 기준 6개월 전
      # @param until_time [Time, String, nil] 종료 시점 (포함). nil 이면 now
      # @return [Result] Success(Pathname) | Failure(:no_entries | :too_many_entries)
      def call(semester_label:, since: nil, until_time: nil)
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        entry_rows = @db[:entries]
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .order(:created_at)
          .all
        return Failure(:no_entries) if entry_rows.size < MIN_ENTRIES
        return Failure(:too_many_entries) if entry_rows.size > MAX_ENTRIES

        stats = compute_stats(entry_rows, since_t, until_t)
        chunks = chunk_by_month(entry_rows)

        body = if @llm_backend
          Infrastructure::AuditLog.with_actor("agent") {
            synthesize_via_llm(semester_label, stats, chunks)
          }
        else
          synthesize_deterministic(semester_label, stats, chunks)
        end

        target = vault_target(semester_label)
        content = build_full_content(semester_label, body, stats, since_t, until_t)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      # 월별 청크 분할 — long-context 한계 우회. 청크 경계는 결정적
      # ("2026-03" 등 created_at 의 YYYY-MM 키).
      def chunk_by_month(entry_rows)
        entry_rows.group_by { |r| r[:created_at].to_s[0, 7] }
          .sort_by { |month, _| month }
          .map { |month, rows| {month: month, entries: rows} }
      end

      def compute_stats(entry_rows, since_t, until_t)
        mode_counts = entry_rows.group_by { |r| r[:mode] }.transform_values(&:count)
        category_counts = entry_rows
          .map { |r| r[:category].to_s }
          .reject(&:empty?)
          .tally
          .sort_by { |_, n| -n }
          .first(TOP_CATEGORY_N)

        # 자주 등장한 학생 — entity_mentions 조인
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
          student_counts: student_counts
        }
      end

      def synthesize_deterministic(_semester_label, stats, chunks)
        lines = []
        lines << "## 이번 학기 흐름"
        lines << ""
        lines << "기간: #{stats[:since].to_s[0, 10]} ~ #{stats[:until].to_s[0, 10]}, 총 #{stats[:total]}건"
        lines << "모드별: " + stats[:mode_counts].map { |m, n| "#{mode_label(m)} #{n}" }.join(" · ")
        lines << ""

        lines << "## 자주 등장한 학생 (상위 #{TOP_STUDENT_N})"
        lines << ""
        if stats[:student_counts].any?
          stats[:student_counts].each do |name, n|
            lines << "- **#{name}**: #{n}회 언급"
          end
        else
          lines << "- (학생 entity 인덱스 없음 — `ExtractEntities` 실행 필요)"
        end
        lines << ""

        lines << "## 자주 다룬 카테고리 (상위 #{TOP_CATEGORY_N})"
        lines << ""
        if stats[:category_counts].any?
          stats[:category_counts].each do |cat, n|
            lines << "- **#{cat}**: #{n}건"
          end
        else
          lines << "- (카테고리 정보 없음)"
        end
        lines << ""

        lines << "## 월별 타임라인"
        lines << ""
        chunks.each do |chunk|
          lines << "### #{chunk[:month]} (#{chunk[:entries].size}건)"
          lines << ""
          chunk[:entries].first(3).each do |row|
            date = row[:created_at].to_s[0, 10]
            title = row[:title].to_s.empty? ? "(제목 없음)" : row[:title]
            lines << "- #{date} #{mode_label(row[:mode])} [[#{row[:path]}]] — #{title}"
          end
          if chunk[:entries].size > 3
            lines << "- … (그 외 #{chunk[:entries].size - 3}건)"
          end
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 회고는 결정적 합성 (통계 + 타임라인). 변화의 순간·잘된·아쉬웠던·다음 학기 준비 분석은 LLM 모드에서._"
        lines.join("\n")
      end

      def mode_label(mode)
        case mode.to_s
        when "memo" then "💭"
        when "note" then "📝"
        when "record" then "📖"
        else "·"
        end
      end

      # 청크별 LLM 요청 → 마지막에 종합 prompt. backend 가 실패하면 결정적 폴백.
      def synthesize_via_llm(semester_label, stats, chunks)
        chunk_summaries = chunks.map { |c|
          summary = @llm_backend.chat(
            system: chunk_system_prompt,
            user: chunk_user_prompt(c)
          )
          {month: c[:month], summary: summary.to_s.strip}
        }

        @llm_backend.chat(
          system: synthesis_system_prompt,
          user: synthesis_user_prompt(semester_label, stats, chunk_summaries)
        ).to_s.strip
      rescue
        synthesize_deterministic(semester_label, stats, chunks)
      end

      def chunk_system_prompt
        <<~TXT
          한국 초등 교사의 한 달 분량 일지를 200~400자로 요약합니다.
          톤: 객관적·관찰. 추측·낙인 금지. 인용은 [[wikilink]] 보존.

          출력 마크다운 (한 단락):
          - 이 달의 주요 흐름 1~2 문장
          - 두드러진 학생·사건 1~2 문장
        TXT
      end

      def chunk_user_prompt(chunk)
        list = chunk[:entries].first(50).map { |row|
          date = row[:created_at].to_s[0, 10]
          title = row[:title].to_s.empty? ? "(메모)" : row[:title]
          excerpt = read_body_excerpt(row[:path])
          "- #{date} #{mode_label(row[:mode])} #{title}: #{excerpt}"
        }.join("\n")
        "# #{chunk[:month]} (#{chunk[:entries].size}건)\n\n#{list}\n"
      end

      def synthesis_system_prompt
        <<~TXT
          한국 초등 교사가 학기 회고를 작성합니다.
          입력은 월별 요약 모음. 톤: 따뜻하고 객관적. 평가가 아닌 관찰. 추측 금지.

          출력 마크다운 섹션 (모두 포함):
          ## 이번 학기 흐름
          ## 변화의 순간들
          ## 잘된 점
          ## 아쉬웠던 점
          ## 다음 학기 준비

          분량: 500~2000자. 인용은 [[wikilink]] 보존.
        TXT
      end

      def synthesis_user_prompt(semester_label, stats, chunk_summaries)
        chunk_text = chunk_summaries.map { |c| "## #{c[:month]}\n#{c[:summary]}" }.join("\n\n")
        student_text = stats[:student_counts].map { |n, c| "#{n}(#{c}회)" }.join(", ")
        category_text = stats[:category_counts].map { |c, n| "#{c}(#{n}건)" }.join(", ")
        <<~TXT
          # 학기: #{semester_label}
          # 기간: #{stats[:since].to_s[0, 10]} ~ #{stats[:until].to_s[0, 10]}
          # 총 #{stats[:total]}건
          # 자주 등장한 학생: #{student_text.empty? ? "(없음)" : student_text}
          # 자주 다룬 카테고리: #{category_text.empty? ? "(없음)" : category_text}

          # 월별 요약
          #{chunk_text}
        TXT
      end

      def read_body_excerpt(rel_path)
        abs = @vault_dir.join(rel_path)
        return "" unless abs.exist?
        parsed = @parser.call(abs.read)
        text = parsed.content.to_s.strip.tr("\n", " ")
        (text.length > EXCERPT_LIMIT) ? "#{text[0, EXCERPT_LIMIT]}…" : text
      rescue
        ""
      end

      def build_full_content(semester_label, body, stats, since_t, until_t)
        fm = {
          "is_synth" => true,
          "synth_target" => "semester:#{semester_label}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => stats[:total],
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_model" => synth_model_label,
          "title" => "학기 회고: #{semester_label}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 학기 회고: #{semester_label}\n\n#{body}\n"
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
