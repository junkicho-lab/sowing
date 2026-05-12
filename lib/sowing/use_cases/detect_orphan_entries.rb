# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 고립 메모 발견 — backlink 0건 entries 식별 (확장 합성기 #5).
    #
    # 위키링크 그래프 인프라(W3) 위에 얹는 발견 도구.
    # "쓴 적 있는데 어떤 다른 글에서도 인용 안 했다 = 잠재적 통찰 / 미발견 패턴".
    # 사용자가 *연결 후보* 를 검토하면서 자기 글의 패턴을 발견.
    #
    # 입력: 모든 entries (또는 since 이후) → IndexRepo.links_to(id) 가 0건인 것
    # 출력:
    #   - 결정적: 고립 entries 목록 + 카테고리·태그·날짜 분포 + 본문 발췌
    #   - LLM: 각 고립 entry → 어떤 기존 entries 와 연결될 수 있는지 후보 (위키링크 패턴 제안)
    #
    # 저장: vault/.sowing/synth/orphans/observations.md (단일 파일, 누적 갱신)
    #
    # 자율 판단 0:
    #   - "이 글이 고립이다" 만 표시. 연결 자체는 사용자가 결정.
    #   - LLM 제안도 "이런 글들과 연결될 수 있을 것 같음" 톤
    class DetectOrphanEntries
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/orphans"
      MIN_ORPHANS = 1
      MAX_ORPHANS = 100        # 너무 많으면 한 화면에 의미 없음
      EXCERPT_LIMIT = 200
      DEFAULT_LOOKBACK_DAYS = 365  # 1년 — 기본 기간

      def initialize(
        db: nil,
        vault_dir: nil,
        safe_writer: nil,
        index_repo: nil,
        llm_backend: nil,
        parser: nil,
        clock: Time
      )
        @db = db || Core::DB.connection
        @vault_dir = Pathname.new((vault_dir || Core::Paths.vault_dir).to_s).expand_path
        @safe_writer = safe_writer || Core::Filesystem::SafeWriter.new
        @index_repo = index_repo || Repositories::IndexRepo.new(db: @db)
        @llm_backend = llm_backend
        @parser = parser || FrontMatterParser::Parser.new(:md)
        @clock = clock
      end

      # @param since [Time, String, nil] 시작 시점. nil = 1년 전
      # @param until_time [Time, String, nil] 종료 시점. nil = now
      # @param exclude_modes [Array<String>] 제외할 mode (default = []. 메모도 분석 대상)
      # @return [Result] Success(Pathname) | Failure(:no_orphans | :too_many_orphans)
      def call(since: nil, until_time: nil, exclude_modes: [])
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_LOOKBACK_DAYS * 86_400)

        ds = @db[:entries]
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
        ds = ds.exclude(mode: exclude_modes) if exclude_modes.any?
        all_rows = ds.order(:created_at).all

        orphans = all_rows.select { |row| @index_repo.links_to(row[:id]).empty? }
        return Failure(:no_orphans) if orphans.size < MIN_ORPHANS
        return Failure(:too_many_orphans) if orphans.size > MAX_ORPHANS

        orphan_meta = orphans.map { |row| build_orphan_meta(row) }

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(orphan_meta, since_t, until_t)
          }
        else
          synthesize_deterministic(orphan_meta, since_t, until_t)
        end

        target = vault_target
        content = build_full_content(body, orphan_meta, since_t, until_t, exclude_modes)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      def build_orphan_meta(row)
        body = read_body(row[:path])
        # 본문 첫 문장
        first_sentence = body.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?).first.to_s
        excerpt = (first_sentence.length > EXCERPT_LIMIT) ? "#{first_sentence[0, EXCERPT_LIMIT]}…" : first_sentence

        # 태그 — entry_tags ⨝ tags 조인
        tags = @db[:entry_tags]
          .join(:tags, id: :tag_id)
          .where(Sequel[:entry_tags][:entry_id] => row[:id])
          .select_map(Sequel[:tags][:name])
          .sort

        # outbound 링크 수 (참고용 — 인용은 했어도 인용은 안 받은 케이스 식별)
        outbound_count = @index_repo.links_from(row[:id]).size

        {
          id: row[:id],
          path: row[:path],
          mode: row[:mode],
          title: row[:title],
          category: row[:category],
          created_at: row[:created_at],
          tags: tags,
          outbound_count: outbound_count,
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

      def synthesize_deterministic(orphan_meta, _since_t, _until_t)
        lines = []
        lines << "## 🌊 고립 entries (#{orphan_meta.size}건)"
        lines << ""
        lines << "_다른 글에서 인용·링크 받지 않은 entries 모음. 잠재적 통찰 — 사용자가 발견._"
        lines << ""

        # 모드별 분포
        mode_counts = orphan_meta.group_by { |o| o[:mode] }.transform_values(&:count)
        lines << "**모드별**: " + mode_counts.map { |m, n| "#{mode_label(m)} #{n}" }.join(" · ")
        lines << ""

        # 카테고리 분포
        cat_counts = orphan_meta.map { |o| o[:category].to_s }.reject(&:empty?).tally.sort_by { |_, n| -n }
        if cat_counts.any?
          lines << "**카테고리**: " + cat_counts.first(5).map { |c, n| "#{c} #{n}" }.join(" · ")
          lines << ""
        end

        # 태그 분포 (전체 — 클러스터 발견 단서)
        all_tags = orphan_meta.flat_map { |o| o[:tags] }.tally.sort_by { |_, n| -n }
        if all_tags.any?
          lines << "**태그**: " + all_tags.first(8).map { |t, n| "##{t}(#{n})" }.join(" · ")
          lines << ""
        end

        lines << "## 📋 entries (시간순)"
        lines << ""
        orphan_meta.sort_by { |o| o[:created_at] }.each_with_index do |o, i|
          title = o[:title].to_s.empty? ? "(제목 없음)" : o[:title]
          tag_str = o[:tags].map { |t| "##{t}" }.join(" ")
          out_str = (o[:outbound_count] > 0) ? " · 외부 링크 #{o[:outbound_count]}건" : ""
          lines << "### [#{i + 1}] #{o[:created_at].to_s[0, 10]} #{mode_label(o[:mode])} #{title}#{out_str}"
          lines << ""
          lines << "> #{o[:excerpt]}"
          lines << ""
          lines << "출처: [[#{o[:path]}]]#{" · #{tag_str}" unless tag_str.empty?}"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (links 테이블 backlink 카운트)._"
        lines << "_연결 후보 제안은 LLM 모드에서. 각 entry 가 *반드시* 연결돼야 한다는 의미는 아닙니다 —"
        lines << "어떤 글은 본질적으로 고립일 수도 있어요._"
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

      def synthesize_via_llm(orphan_meta, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(orphan_meta, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(orphan_meta, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사의 글 모음에서 *연결되지 않은* entries 를 검토합니다.
          입력은 backlink 0건인 entries 의 발췌·태그·카테고리.
          톤: 발견·궁금증. "왜 이게 고립됐는가" X, "어떤 기존 글과 연결될 수 있는가" O.
          본문에 없는 사실 만들기 금지.

          출력 마크다운:
          ## 🌊 고립 entries 의 패턴 (있다면)
          - 카테고리·태그 분포에서 보이는 것 1~2 문장

          ## 🔗 연결 후보 제안
          - 각 entry 별로 연결 가능성 있는 *주제·키워드* 1~2개 제안
          - 형식: "[#] 본문 키워드 → 어떤 기존 entries 와 연결 가능 (예: ...)"

          ## 💭 어떤 글은 고립일 수도
          - 본질적으로 고립인 entries 가 있을 수 있음을 인정 (단정 X)

          분량: 400~1000자.
        TXT
      end

      def llm_user_prompt(orphan_meta, since_t, until_t)
        list = orphan_meta.first(20).map.with_index { |o, i|
          tag_str = o[:tags].any? ? " #{o[:tags].map { |t| "##{t}" }.join(" ")}" : ""
          cat_str = o[:category].to_s.empty? ? "" : " · #{o[:category]}"
          "[#{i + 1}] #{o[:created_at].to_s[0, 10]} #{mode_label(o[:mode])}#{cat_str}#{tag_str}: #{o[:excerpt]}"
        }.join("\n")
        <<~TXT
          # 기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}
          # 고립 entries 총 #{orphan_meta.size}건 (위 20건 발췌)

          #{list}
        TXT
      end

      def build_full_content(body, orphan_meta, since_t, until_t, exclude_modes)
        all_tags = orphan_meta.flat_map { |o| o[:tags] }.uniq.sort
        fm = {
          "is_synth" => true,
          "synth_target" => "orphans:observations",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => orphan_meta.size,
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_excluded_modes" => exclude_modes,
          "synth_orphan_tags" => all_tags,
          "synth_model" => synth_model_label,
          "title" => "고립 entries 관찰"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 고립 entries 관찰\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target
        @vault_dir.join(SYNTH_DIR, "observations.md")
      end
    end
  end
end
