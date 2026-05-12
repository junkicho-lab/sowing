# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 학생 묘사의 시간순 변화 / 논리 비일관성 탐지 (W21-T03).
    #
    # ADR-013 의 Phase 12 요건 (Phase 11~12 합성기 패턴 그대로 확장):
    #   - 결정적 fallback (반의어 차원 매칭, LLM 미사용 모드 1급)
    #   - LLM 옵트인 (변화 시점·맥락 해석은 LLM 모드에서만)
    #   - 톤: "모순" 이 아닌 *변화·발견* — 사용자가 비판이 아닌 통찰로 받아들이도록
    #     ("민준이는 4월엔 '소극적'으로 5월엔 '적극적'으로 묘사 — 변화 시점 5/5")
    #   - audit log actor=agent 자동 마킹 (`with_actor` 블록)
    #   - 자율 판단 0 — 인용 근거(entry path + 문장) 항상 함께 제시
    #
    # 결정적 모드 한계 인정:
    #   - 반의어 사전 기반 — 사전 외 묘사 (예: "내성적/외향적" 외 다른 어휘)는 미탐지
    #   - false positive 가능 — 같은 차원의 두 표현이 *같은 학생을 다른 시기에* 묘사한
    #     경우만 탐지하지만, 사용자가 같은 차원을 *맥락 다르게* 쓴 경우는 변화로 잘못 봄.
    #     → 그래서 결과는 "변화 후보" 로만 표현, 사용자가 검토.
    #
    # 저장 위치: vault/.sowing/synth/contradictions/observations.md
    #   - 단일 파일 — 학생 전체에 걸친 관찰 누적
    #   - frontmatter `synth_target: "contradictions:observations"`
    class DetectContradictions
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/contradictions"
      DEFAULT_WINDOW_DAYS = 180  # 6개월 (학기)
      MIN_OBSERVATIONS = 1       # 1명만 변화 보여도 의미 있음
      MIN_MENTIONS_PER_STUDENT = 2  # 한 학생에 2건 이상 mention 있어야 변화 추적 가능
      EXCERPT_LIMIT = 200

      # 반의어 차원 — 한 *차원* 의 양 끝 묘사가 다른 시기에 등장하면 변화 후보.
      # 각 차원: {dimension: 라벨, low: [낮은 끝 어휘], high: [높은 끝 어휘]}
      ANTONYM_DIMENSIONS = [
        {
          dimension: "참여도",
          low: %w[소극 소극적 위축 조용 침묵 발표를\ 안 발표를\ 거의\ 안 발표\ 안\ 함 시선\ 안 듣는\ 역할],
          high: %w[적극 적극적 자원 발표\ 자원 발표를\ 자원 활발 능동 주도]
        },
        {
          dimension: "집중도",
          low: %w[산만 집중\ 안 집중력\ 부족 딴짓 멍하],
          high: %w[집중 몰입 차분 진지]
        },
        {
          dimension: "이해도",
          low: %w[어려워 못\ 따라 따라오지\ 못 부진 헤매 헷갈],
          high: %w[잘\ 이해 이해도\ 높 또래\ 이상 평균\ 이상 빠르게\ 풀]
        },
        {
          dimension: "협력성",
          low: %w[혼자 외톨이 모둠\ 안 어울리지\ 못 갈등 다툼],
          high: %w[협력 모둠\ 잘 친구들과\ 잘 도와 사회자\ 역할]
        }
      ].freeze

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

      # @param since [Time, String, nil] 시작 시점 (포함). nil 이면 6개월 전
      # @param until_time [Time, String, nil] 종료 시점 (포함). nil 이면 now
      # @return [Result] Success(Pathname) | Failure(:no_observations)
      def call(since: nil, until_time: nil)
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since) || (until_t - DEFAULT_WINDOW_DAYS * 86_400)

        students = @db[:entities].where(type: "student").all
        observations = students.flat_map { |e| detect_for_student(e, since_t, until_t) }
        return Failure(:no_observations) if observations.size < MIN_OBSERVATIONS

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(observations, since_t, until_t)
          }
        else
          synthesize_deterministic(observations, since_t, until_t)
        end

        target = vault_target
        content = build_full_content(body, observations, since_t, until_t)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      # 학생별 시간순 mention 분석 → ANTONYM_DIMENSIONS 양 끝 매칭 페어.
      # 결과: [{student, dimension, low_evidence: {path, sentence, date}, high_evidence: {...}}]
      def detect_for_student(entity, since_t, until_t)
        mention_rows = @db[:entity_mentions].where(entity_id: entity[:id]).select_map(:entry_id)
        return [] if mention_rows.size < MIN_MENTIONS_PER_STUDENT

        entry_rows = @db[:entries]
          .where(id: mention_rows)
          .where { (created_at >= since_t.iso8601) & (created_at <= until_t.iso8601) }
          .order(:created_at)
          .all
        return [] if entry_rows.size < MIN_MENTIONS_PER_STUDENT

        # 각 entry 의 각 문장 — 학생 이름 포함 문장만 분석
        student_name = entity[:name]
        sentences_with_meta = []
        entry_rows.each do |row|
          body = read_body(row[:path])
          next if body.empty?
          sentences(body).each do |sent|
            next unless sent.include?(student_name)
            sentences_with_meta << {
              path: row[:path],
              date: row[:created_at].to_s[0, 10],
              sentence: clip(sent)
            }
          end
        end

        # 각 차원별로 low/high 매칭 → 둘 다 있으면 변화 후보
        observations = []
        ANTONYM_DIMENSIONS.each do |dim|
          low_hits = sentences_with_meta.select { |s| match_any?(s[:sentence], dim[:low]) }
          high_hits = sentences_with_meta.select { |s| match_any?(s[:sentence], dim[:high]) }
          next if low_hits.empty? || high_hits.empty?

          # 시간순 — low 가 먼저인지 high 가 먼저인지에 따라 변화 방향 표시
          first_low = low_hits.min_by { |s| s[:date] }
          first_high = high_hits.min_by { |s| s[:date] }
          observations << {
            student: student_name,
            dimension: dim[:dimension],
            direction: (first_low[:date] < first_high[:date]) ? :low_to_high : :high_to_low,
            low_evidence: first_low,
            high_evidence: first_high
          }
        end

        observations
      end

      def read_body(rel_path)
        abs = @vault_dir.join(rel_path)
        return "" unless abs.exist?
        parsed = @parser.call(abs.read)
        parsed.content.to_s
      rescue
        ""
      end

      def sentences(text)
        text.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?)
      end

      def match_any?(sentence, keywords)
        keywords.any? do |kw|
          pattern = kw.gsub('\\ ', " ")
          sentence.include?(pattern)
        end
      end

      def clip(text)
        cleaned = text.tr("\n", " ").strip
        (cleaned.length > EXCERPT_LIMIT) ? "#{cleaned[0, EXCERPT_LIMIT]}…" : cleaned
      end

      def synthesize_deterministic(observations, _since_t, _until_t)
        lines = []
        lines << "## 🔄 학생 묘사의 변화 후보 (#{observations.size}건)"
        lines << ""
        lines << "_시간 흐름에 따라 같은 학생이 다른 묘사로 표현된 사례. 모순이 아닌 *변화·발견* 으로._"
        lines << ""

        observations.each_with_index do |obs, i|
          arrow = (obs[:direction] == :low_to_high) ? "→ 향상" : "→ 후퇴"
          lines << "### [#{i + 1}] #{obs[:student]} · #{obs[:dimension]} #{arrow}"
          lines << ""
          first = (obs[:direction] == :low_to_high) ? obs[:low_evidence] : obs[:high_evidence]
          second = (obs[:direction] == :low_to_high) ? obs[:high_evidence] : obs[:low_evidence]
          lines << "- **#{first[:date]}** [[#{first[:path]}]]"
          lines << "  > #{first[:sentence]}"
          lines << "- **#{second[:date]}** [[#{second[:path]}]]"
          lines << "  > #{second[:sentence]}"
          lines << ""
          lines << "_변화 시점: #{first[:date]} → #{second[:date]}. 분기점이 된 사건이 있었는지 검토._"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (반의어 차원 #{ANTONYM_DIMENSIONS.size}종 매칭)._"
        lines << "_변화 시점·맥락 해석은 LLM 모드에서. 각 변화는 후보일 뿐 — 사용자가 검토 후 *발견* 으로 받아들일 것._"
        lines.join("\n")
      end

      def synthesize_via_llm(observations, since_t, until_t)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(observations, since_t, until_t)
        ).to_s.strip
      rescue
        synthesize_deterministic(observations, since_t, until_t)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 학생 묘사의 시간 흐름 변화를 검토합니다.
          입력은 결정적 매칭으로 1차 추출된 변화 후보 (반의어 차원의 양 끝).
          톤: 통찰. 비판·낙인·단정 금지. "모순" 이 아닌 *변화·발견*.
          출처는 [[wikilink]] 보존. 본문에 없는 사실 만들기 금지.

          출력 마크다운 (각 후보당):
          ### {학생} · {차원}
          - 변화 시점: {date_low} → {date_high}
          - 인용 [#1] [#2]
          - 가능한 분기점: 본문에 명시된 사건만 (없으면 "분기점 미확인")
          - 다음 관찰 제안: 1~2 문장

          분량: 후보 1건당 100~200자.
        TXT
      end

      def llm_user_prompt(observations, since_t, until_t)
        list = observations.map.with_index { |o, i|
          "[#{i + 1}] #{o[:student]} · #{o[:dimension]}\n" \
          "  - #{o[:low_evidence][:date]}: #{o[:low_evidence][:sentence]}\n" \
          "  - #{o[:high_evidence][:date]}: #{o[:high_evidence][:sentence]}"
        }.join("\n\n")
        "# 기간: #{since_t.to_s[0, 10]} ~ #{until_t.to_s[0, 10]}\n\n# 변화 후보 #{observations.size}건\n#{list}\n"
      end

      def build_full_content(body, observations, since_t, until_t)
        student_names = observations.map { |o| o[:student] }.uniq
        fm = {
          "is_synth" => true,
          "synth_target" => "contradictions:observations",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => observations.size,
          "synth_period_since" => since_t.iso8601,
          "synth_period_until" => until_t.iso8601,
          "synth_students" => student_names,
          "synth_model" => synth_model_label,
          "title" => "학생 묘사 변화 후보"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 학생 묘사 변화 후보\n\n#{body}\n"
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
