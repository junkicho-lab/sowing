# frozen_string_literal: true

module Sowing
  module Eval
    # 한국어 교사 도메인 특화 평가 차원 (W13-T04).
    #
    # 5 차원 모두 *결정적 휴리스틱* — LLM 미사용. 정규식·어휘 매칭으로 0~5 점수.
    # 결정적이라 self-consistency kappa = 1.0 보장 (cosine 회귀 자동 검증).
    #
    # 진짜 사람-judge 카파 ≥ 0.7 은 Phase 11+ 에서 실제 사람 평가 데이터 모인 후
    # 별도 검증 (현재는 휴리스틱과 LLM-judge 평가의 분리만 보장).
    #
    # 차원:
    #   - honorific_consistency: 높임말 vs 평어 혼용 정도
    #   - korean_date_format: 한국식(YYYY년 M월) vs ISO(YYYY-MM-DD) 일관성
    #   - student_anonymity: 학생 이름 노출 패턴 (가상명/단일이름 vs 풀네임)
    #   - classroom_context: 교실 어휘 풍부도
    #   - tag_korean: 한글 태그(#가-힣) 존재
    module KoreanDimensions
      # 문장 분리 — 종결어미는 문장 마지막 어절에서만 검사 (false positive 줄임).
      SENTENCE_SPLIT_RE = /[.!?。\n]+/
      # 문장 마지막 어절의 종결어미 패턴.
      # `니다$` 는 입니다/됩니다/합니다/했습니다 모두 커버.
      # 검사 순서: 높임 먼저 → 평어 (높임이 평어 superset 인 "X니다" 케이스 처리).
      HONORIFIC_ENDING_RE = /(?:니다|어요|아요|예요|이에요)$/
      INFORMAL_ENDING_RE = /(?:다|네|군|구나)$/

      # 한국식 날짜: 2026년 5월 8일 / 5월 8일 / 2026.5.8
      KOREAN_DATE_RE = /\d{4}년\s*\d{1,2}월\s*\d{1,2}일|\d{1,2}월\s*\d{1,2}일/
      # ISO 8601 날짜: 2026-05-08 / 2026/05/08
      ISO_DATE_RE = %r{\d{4}[-/.]\d{2}[-/.]\d{2}}

      # 풀네임 의심 — 한국 풀네임은 거의 3음절 (성씨 1글자 + 이름 2글자). 4음절도 가능.
      # 단순 surname prefix 매칭은 false positive 폭발 → 단어 경계 + 정확한 글자수 + 입자/구두점 lookahead 로 정밀화.
      KOREAN_SURNAMES = %w[김 이 박 최 정 강 조 윤 장 임 한 오 서 신 권 황 안 송 전 홍].freeze
      # (앞이 단어 시작) + 성씨 + 정확 2 한글 + (단어 끝 표지 — 공백/구두점/조사 패턴/문서 끝)
      FULL_NAME_RE = /(?<=^|\s|[.,!?])(?:#{KOREAN_SURNAMES.join("|")})[가-힣]{2}(?=\s|[.,!?]|이가\b|$)/

      # 교실 어휘 사전 — 한국 K-12 교사 일지에서 흔히 등장.
      CLASSROOM_VOCABULARY = %w[
        수업 학생 교실 모둠 발표 토론 활동 회고 평가
        과제 숙제 교과서 단원 차시 학기 학년 담임
        학부모 상담 출결 학급 교사 학교
      ].freeze

      KOREAN_TAG_RE = /#[가-힣]+/

      module_function

      # @param text [String]
      # @return [Integer] 0~5 — 종결어미 일관성 (높임 vs 평어 혼용 정도).
      #   문장 분리 후 각 문장 마지막 어절만 검사 — 중간 글자 false positive 회피.
      def honorific_consistency(text)
        sentences = text.split(SENTENCE_SPLIT_RE).map(&:strip).reject(&:empty?)
        honorific = 0
        informal = 0

        sentences.each do |sent|
          last_word = sent.split(/\s+/).last.to_s
          if last_word.match?(HONORIFIC_ENDING_RE)
            honorific += 1
          elsif last_word.match?(INFORMAL_ENDING_RE)
            informal += 1
          end
        end

        total = honorific + informal
        return 5 if total <= 1 # 종결어미 식별 0~1 — 검증 불가 → perfect

        ratio = [honorific, informal].max.to_f / total
        score_from_ratio(ratio)
      end

      # @return [Integer] 0~5 — 한국식 날짜와 ISO 날짜 혼용 일관성
      def korean_date_format(text)
        kr = text.scan(KOREAN_DATE_RE).size
        iso = text.scan(ISO_DATE_RE).size
        total = kr + iso
        return 5 if total <= 1 # 날짜 없거나 1개 — perfect

        ratio = [kr, iso].max.to_f / total
        score_from_ratio(ratio)
      end

      # 일관성 비율 (0.5~1.0) → 0~5 점수.
      # private API. 부동소수 비교 안전 (≥ 임계값).
      def score_from_ratio(ratio)
        return 5 if ratio >= 0.999  # 사실상 100% (부동소수 안전)
        return 4 if ratio >= 0.85
        return 3 if ratio >= 0.7
        return 2 if ratio >= 0.55
        return 1 if ratio >= 0.4
        0
      end

      # @return [Integer] 0~5 — 학생 익명성 (풀네임 노출 패널티)
      def student_anonymity(text)
        full_names = text.scan(FULL_NAME_RE).size
        case full_names
        when 0 then 5  # 풀네임 0 — 완벽
        when 1 then 4
        when 2 then 3
        when 3 then 2
        when 4 then 1
        else 0
        end
      end

      # @return [Integer] 0~5 — 교실 어휘 풍부도 (CLASSROOM_VOCABULARY 매칭 종류 수)
      def classroom_context(text)
        matches = CLASSROOM_VOCABULARY.count { |word| text.include?(word) }
        case matches
        when 0 then 0
        when 1..2 then 1
        when 3..4 then 2
        when 5..6 then 3
        when 7..8 then 4
        else 5              # 9+ 종류 — 풍부
        end
      end

      # @return [Integer] 0~5 — 한글 태그 존재
      def tag_korean(text)
        tags = text.scan(KOREAN_TAG_RE).uniq
        case tags.size
        when 0 then 0
        when 1 then 2
        when 2 then 3
        when 3 then 4
        else 5
        end
      end

      # 모든 차원 일괄 평가.
      # @return [Hash{String => Integer}] dimension → score
      def evaluate_all(text)
        {
          "honorific_consistency" => honorific_consistency(text),
          "korean_date_format" => korean_date_format(text),
          "student_anonymity" => student_anonymity(text),
          "classroom_context" => classroom_context(text),
          "tag_korean" => tag_korean(text)
        }
      end

      # 사용 가능 차원 이름.
      def dimensions
        %w[honorific_consistency korean_date_format student_anonymity classroom_context tag_korean]
      end
    end
  end
end
