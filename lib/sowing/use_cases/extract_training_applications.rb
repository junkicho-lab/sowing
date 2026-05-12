# frozen_string_literal: true

require "dry/monads"
require "front_matter_parser"
require "json"
require "pathname"
require "time"
require "yaml"

module Sowing
  module UseCases
    # 연수 노트 ↔ 실제 수업 적용 사례 매칭 (확장 합성기 #3).
    #
    # 입력:
    #   - 연수 노트 1건 (notes 의 `category="trainings"`) — slug = entry id
    #   - 그 후 일정 기간 (default 90일) 안의 entries (memo / note / record)
    #
    # 매칭 알고리즘 (결정적):
    #   - 연수 노트 본문에서 핵심 키워드 (명사 위주) 추출
    #   - 그 키워드들이 후속 entries 본문에 등장하는 sentence 단위 인용
    #   - 적용 시점 (연수 후 N일 차) 표시
    #
    # 한계 인정 (자율 판단 0, ADR-013):
    #   - "이 entry 가 연수의 적용 사례다" 라고 단정 X — *키워드 매칭 후보* 로 표현
    #   - 연수 노트 자체에 키워드가 명확하지 않으면 매칭 어려움 → 사용자가 LLM 모드로
    #
    # LLM 모드:
    #   - 연수 본문 + 후속 entries 인용 → "어떤 학습이 적용됐고, 어떤 영역이 미적용인가"
    #   - 단정 X — "본문에 명시된 사례 만"
    #
    # 저장 위치: vault/.sowing/synth/trainings/{training_slug}.md
    #   - 연수 1건당 1 파일 (학기당 여러 연수 가능)
    #   - synth_target: "training:{training_id}"
    class ExtractTrainingApplications
      include Dry::Monads[:result]

      SYNTH_DIR = ".sowing/synth/trainings"
      DEFAULT_FOLLOWUP_DAYS = 90  # 연수 후 3개월
      MIN_KEYWORD_LENGTH = 2       # 너무 짧으면 noise (예: "이", "학")
      MAX_KEYWORDS = 12            # 키워드 폭발 방지
      MAX_FOLLOWUP_ENTRIES = 200   # 안전 가드
      EXCERPT_LIMIT = 200

      # 한국어 불용어 — 키워드 추출 시 제외 (조사·일반 명사·시간 표현).
      STOPWORDS = %w[
        오늘 내일 어제 학생 학생들 우리 모두 수업 시간 활동 정리 진행
        이번 다음 지난 이런 그런 저런 어떤 모든 같은 다른 새로 처음
        내용 결과 사항 부분 경우 정도 만큼 보다 위해 통해 대해 관해
        있다 없다 하다 되다 이다 그러다 그렇다 좋다 어렵다
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

      # @param training_id [String] 연수 노트의 entry id (notes/trainings/*.md)
      # @param followup_days [Integer] 연수 후 추적 기간 (default 90일)
      # @return [Result] Success(Pathname) | Failure(:training_not_found | :no_keywords | :too_many_followups)
      def call(training_id:, followup_days: DEFAULT_FOLLOWUP_DAYS)
        training = @db[:entries].where(id: training_id, mode: "note", category: "trainings").first
        return Failure(:training_not_found) if training.nil?

        training_body = read_body(training[:path])
        return Failure(:no_training_body) if training_body.empty?

        keywords = extract_keywords(training_body)
        return Failure(:no_keywords) if keywords.empty?

        followup_window_end = Time.parse(training[:created_at].to_s) + followup_days * 86_400
        followup_rows = @db[:entries]
          .exclude(id: training_id)
          .where { (created_at > training[:created_at]) & (created_at <= followup_window_end.iso8601) }
          .order(:created_at)
          .all
        return Failure(:too_many_followups) if followup_rows.size > MAX_FOLLOWUP_ENTRIES

        applications = match_applications(training, keywords, followup_rows)

        body = if @llm_backend
          Core::AuditLog.with_actor("agent") {
            synthesize_via_llm(training, keywords, applications, followup_days)
          }
        else
          synthesize_deterministic(training, keywords, applications, followup_days)
        end

        target = vault_target(training_id)
        content = build_full_content(training, body, keywords, applications, followup_days)
        @safe_writer.atomic_write(target, content)

        Success(target)
      end

      private

      def read_body(rel_path)
        abs = @vault_dir.join(rel_path)
        return "" unless abs.exist?
        parsed = @parser.call(abs.read)
        parsed.content.to_s
      rescue
        ""
      end

      # 연수 본문 → 한국어 어절 분리 → 불용어·조사 제외 → 빈도 상위 키워드.
      # 결정적 휴리스틱 — 정밀하지 않지만 LLM 모드 1차 입력으로 충분.
      def extract_keywords(text)
        # 어절 분리 (공백·구두점·괄호)
        tokens = text.split(/[\s.,!?。()\[\]「」『』【】\-—–:;]+/).reject(&:empty?)

        freq = Hash.new(0)
        tokens.each do |token|
          # 한국어 어간 추출 — 조사 제거 (간단 휴리스틱: 마지막 1~2 음절이 조사면 제거)
          stem = strip_particle(token)
          next if stem.length < MIN_KEYWORD_LENGTH
          next if STOPWORDS.include?(stem)
          # 숫자만 / 영문만 토큰은 제외 (한국어 키워드 우선)
          next unless stem.match?(/\p{Hangul}/)
          freq[stem] += 1
        end

        freq.sort_by { |_, c| -c }.first(MAX_KEYWORDS).map(&:first)
      end

      # 한국어 조사 간단 제거 — 빈도 카운트 정확도 향상용 (perfect 아님).
      KOREAN_PARTICLES = %w[은 는 이 가 을 를 의 와 과 에 도 만 으로 로 부터 까지 에서 께 께서].freeze

      def strip_particle(token)
        KOREAN_PARTICLES.each do |p|
          if token.length > p.length && token.end_with?(p)
            return token[0...-p.length]
          end
        end
        token
      end

      # 후속 entries 의 각 문장이 키워드 1개 이상 포함하면 적용 후보.
      # D+N 은 *달력 일수* (시각 무관) — 사용자가 직관적으로 이해하는 단위.
      # 결과: [{path, date, days_after, keywords_matched, sentence}]
      def match_applications(training, keywords, followup_rows)
        training_date = Time.parse(training[:created_at].to_s).to_date
        applications = []

        followup_rows.each do |row|
          body = read_body(row[:path])
          next if body.empty?

          body.split(/[.!?。\n]+/).each do |sent|
            sent = sent.strip
            next if sent.length < 5

            matched = keywords.select { |kw| sent.include?(kw) }
            next if matched.empty?

            entry_date = Time.parse(row[:created_at].to_s).to_date
            applications << {
              path: row[:path],
              date: row[:created_at].to_s[0, 10],
              days_after: (entry_date - training_date).to_i,
              keywords_matched: matched,
              sentence: clip(sent),
              mode: row[:mode]
            }
          end
        end

        # entry path 기준 dedupe — 같은 entry 가 여러 문장 매칭돼도 첫 문장만
        applications.uniq { |a| a[:path] }
      end

      def clip(text)
        cleaned = text.tr("\n", " ").strip
        (cleaned.length > EXCERPT_LIMIT) ? "#{cleaned[0, EXCERPT_LIMIT]}…" : cleaned
      end

      def synthesize_deterministic(training, keywords, applications, followup_days)
        lines = []
        lines << "## 📚 연수 핵심 키워드 (#{keywords.size}개, 빈도순)"
        lines << ""
        lines << keywords.map { |k| "`#{k}`" }.join(" · ")
        lines << ""

        lines << "## ✨ 적용 후보 (#{applications.size}건, 연수 후 #{followup_days}일 추적)"
        lines << ""
        if applications.any?
          lines << "_연수 키워드와 본문이 매칭된 후속 entries. **자동 추론 — 사용자 검토 필요**._"
          lines << ""
          applications.each_with_index do |app, i|
            kw = app[:keywords_matched].first(3).map { |k| "`#{k}`" }.join(" · ")
            lines << "### [#{i + 1}] #{app[:date]} (D+#{app[:days_after]}일) · #{kw}"
            lines << ""
            lines << "> #{app[:sentence]}"
            lines << ""
            lines << "출처: [[#{app[:path]}]]"
            lines << ""
          end
        else
          lines << "_연수 후 #{followup_days}일 안에 키워드 매칭 entries 가 없습니다._"
          lines << "_연수 적용은 시간이 더 걸릴 수 있어요. 또는 LLM 모드에서 의미 단위 매칭을._"
          lines << ""
        end

        lines << "---"
        lines << ""
        lines << "_본 결과는 결정적 합성 (키워드 빈도 상위 #{MAX_KEYWORDS}개 + 후속 entries 문장 단위 매칭)._"
        lines << "_의미 매칭·미적용 영역 분석은 LLM 모드에서. 각 매칭은 *후보* 일 뿐 — 실제 적용 여부는 교사 본인이 판단._"
        lines.join("\n")
      end

      def synthesize_via_llm(training, keywords, applications, followup_days)
        @llm_backend.chat(
          system: llm_system_prompt,
          user: llm_user_prompt(training, keywords, applications, followup_days)
        ).to_s.strip
      rescue
        synthesize_deterministic(training, keywords, applications, followup_days)
      end

      def llm_system_prompt
        <<~TXT
          한국 초등 교사가 받은 연수의 실제 수업 적용 사례를 점검합니다.
          입력: 연수 본문 + 키워드 + 결정적 매칭된 후속 entries (키워드 일치).
          톤: 발견·통찰. 평가·비판 X. 본문에 없는 사실 만들기 금지.

          출력 마크다운 (모든 섹션 포함):
          ## 📚 연수 핵심 요약
          - 1~2 문장. 본문 기반.

          ## ✨ 적용된 사례
          - 인용 [#] + 적용 시점 (D+N일)
          - 단정 X — "~ 라는 인용이 D+N일에 발견됨"

          ## 🌱 미적용 영역 (연수 키워드 중 후속 entries 에 등장 안 한 것)
          - 키워드 중 적용 사례 없는 영역. "다음에 시도해 볼 만함" 톤

          ## 💡 다음 적용 후보
          - 본문 기반 구체 행동 1~3개

          분량: 400~1200자.
        TXT
      end

      def llm_user_prompt(training, keywords, applications, followup_days)
        training_body = read_body(training[:path])
        apps = applications.map.with_index { |a, i|
          kw = a[:keywords_matched].first(3).join(" / ")
          "[#{i + 1}] #{a[:date]} (D+#{a[:days_after]}일) [#{kw}]: #{a[:sentence]}"
        }.join("\n")
        <<~TXT
          # 연수: #{training[:title] || training[:id]}
          # 일자: #{training[:created_at].to_s[0, 10]}
          # 추적 기간: #{followup_days}일

          # 연수 본문
          #{training_body[0, 1500]}

          # 연수 키워드 (#{keywords.size}개)
          #{keywords.join(" / ")}

          # 적용 후보 (#{applications.size}건)
          #{apps.empty? ? "(없음)" : apps}
        TXT
      end

      def build_full_content(training, body, keywords, applications, followup_days)
        unmatched = keywords - applications.flat_map { |a| a[:keywords_matched] }.uniq
        fm = {
          "is_synth" => true,
          "synth_target" => "training:#{training[:id]}",
          "synth_at" => @clock.now.iso8601,
          "synth_source_count" => applications.size,
          "synth_training_path" => training[:path].to_s,
          "synth_training_date" => training[:created_at].to_s,
          "synth_followup_days" => followup_days,
          "synth_keywords" => keywords,
          "synth_unmatched_keywords" => unmatched,
          "synth_model" => synth_model_label,
          "title" => "연수 적용 추적: #{training[:title] || training[:id]}"
        }
        yaml_body = YAML.dump(fm).delete_prefix("---\n")
        "---\n#{yaml_body}---\n\n# 연수 적용 추적\n\n원본 연수: [[#{training[:path]}]] (#{training[:created_at].to_s[0, 10]})\n\n#{body}\n"
      end

      def synth_model_label
        @llm_backend ? @llm_backend.name : "deterministic"
      end

      def vault_target(training_id)
        @vault_dir.join(SYNTH_DIR, "#{training_id}.md")
      end
    end
  end
end
