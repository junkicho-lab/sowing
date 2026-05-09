# frozen_string_literal: true

module Sowing
  module Eval
    # Cohen's quadratic weighted kappa — 사람-judge vs LLM-judge 일치 측정 (W13-T02).
    #
    # ROADMAP 검증: kappa ≥ 0.8 면 LLM-judge 신뢰 가능 → CI 도입 (W13-T03).
    # ordinal 점수(0~5) 에 적합. 단순 일치율보다 chance-corrected.
    #
    # 공식:
    #   kappa = 1 - (Σ w_ij × O_ij) / (Σ w_ij × E_ij)
    # quadratic weights: w_ij = (i - j)² / (N - 1)²
    module Kappa
      module_function

      # 두 평가자의 점수 배열로 kappa 계산.
      # @param raters_a [Array<Integer>] 첫 평가자 (예: 사람) 점수
      # @param raters_b [Array<Integer>] 두 번째 평가자 (예: LLM) 점수, 같은 길이
      # @param max_score [Integer] 최대 점수 (기본 5 — 0~5 ordinal)
      # @return [Float] -1.0 ~ 1.0 (1.0 완전 일치, 0 chance, 음수 불일치)
      def quadratic_weighted(raters_a, raters_b, max_score: 5)
        raise ArgumentError, "두 평가자 배열 길이 불일치" unless raters_a.size == raters_b.size
        raise ArgumentError, "빈 배열" if raters_a.empty?

        n = raters_a.size
        categories = (0..max_score).to_a
        c = categories.size

        # 빈도 행렬 O_ij
        observed = build_matrix(raters_a, raters_b, categories)

        # 주변 분포로 기대 행렬 E_ij
        row_totals = observed.map(&:sum)
        col_totals = (0...c).map { |j| observed.map { |row| row[j] }.sum }
        expected = (0...c).map { |i|
          (0...c).map { |j|
            row_totals[i] * col_totals[j] / n.to_f
          }
        }

        # quadratic weights
        denom_w = (c - 1)**2
        weights = (0...c).map { |i|
          (0...c).map { |j| (i - j)**2 / denom_w.to_f }
        }

        num = 0.0
        den = 0.0
        (0...c).each do |i|
          (0...c).each do |j|
            num += weights[i][j] * observed[i][j]
            den += weights[i][j] * expected[i][j]
          end
        end

        return 1.0 if den.zero?
        1.0 - num / den
      end

      # 단순 (unweighted) Cohen's kappa — 일치/불일치만 봄.
      # ordinal 데이터에서는 quadratic_weighted 권장.
      def simple(raters_a, raters_b)
        raise ArgumentError, "길이 불일치" unless raters_a.size == raters_b.size
        return 1.0 if raters_a.empty?

        agreement = raters_a.zip(raters_b).count { |a, b| a == b }
        po = agreement.to_f / raters_a.size

        all = (raters_a + raters_b).uniq
        pe = all.sum { |cat|
          a_freq = raters_a.count(cat).to_f / raters_a.size
          b_freq = raters_b.count(cat).to_f / raters_b.size
          a_freq * b_freq
        }

        return 1.0 if (1.0 - pe).abs < 1e-10
        (po - pe) / (1.0 - pe)
      end

      # @private
      def build_matrix(raters_a, raters_b, categories)
        c = categories.size
        matrix = Array.new(c) { Array.new(c, 0) }
        raters_a.zip(raters_b).each do |a, b|
          i = categories.index(a) || next
          j = categories.index(b) || next
          matrix[i][j] += 1
        end
        matrix
      end
    end
  end
end
