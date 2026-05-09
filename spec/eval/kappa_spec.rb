# frozen_string_literal: true

RSpec.describe Sowing::Eval::Kappa do
  describe ".quadratic_weighted" do
    it "완전 일치 → kappa = 1.0" do
      a = [3, 4, 5, 2, 1]
      kappa = described_class.quadratic_weighted(a, a.dup)
      expect(kappa).to be_within(1e-9).of(1.0)
    end

    it "완전 반대 (5↔0, 4↔1, 3↔2) → 음수 kappa" do
      a = [5, 4, 3, 2, 1, 0]
      b = [0, 1, 2, 3, 4, 5]
      kappa = described_class.quadratic_weighted(a, b)
      expect(kappa).to be < 0
    end

    it "랜덤 (chance level) → kappa ≈ 0" do
      # 평가자 간 무관 — 두 분포는 같지만 짝이 임의
      a = (0..5).to_a * 30      # 180건, 균등 분포
      b = a.shuffle(random: Random.new(42))
      kappa = described_class.quadratic_weighted(a, b)
      expect(kappa.abs).to be < 0.2 # chance 근방
    end

    it "ROADMAP 검증 시나리오 — 사람·LLM 강한 일치 (kappa ≥ 0.8)" do
      # 거의 같은 점수, 가끔 1점 차이
      a = [5, 5, 4, 4, 3, 3, 2, 2, 1, 1]
      b = [5, 4, 4, 4, 3, 3, 2, 2, 1, 0] # 3건만 1점 차이
      kappa = described_class.quadratic_weighted(a, b)
      expect(kappa).to be >= 0.8
    end

    it "길이 불일치 → ArgumentError" do
      expect { described_class.quadratic_weighted([1, 2], [1]) }.to raise_error(ArgumentError, /길이 불일치/)
    end

    it "빈 배열 → ArgumentError" do
      expect { described_class.quadratic_weighted([], []) }.to raise_error(ArgumentError, /빈 배열/)
    end

    it "max_score 인자로 범위 조정 가능" do
      # 0~3 범위 평가
      a = [3, 2, 1, 0]
      kappa = described_class.quadratic_weighted(a, a.dup, max_score: 3)
      expect(kappa).to be_within(1e-9).of(1.0)
    end
  end

  describe ".simple (unweighted)" do
    it "완전 일치 → 1.0" do
      a = [1, 2, 3, 4, 5]
      expect(described_class.simple(a, a.dup)).to be_within(1e-9).of(1.0)
    end

    it "랜덤 chance → 0 근방" do
      a = (0..5).to_a * 30
      b = a.shuffle(random: Random.new(7))
      kappa = described_class.simple(a, b)
      expect(kappa.abs).to be < 0.2
    end

    it "단일 카테고리 (모두 같은 값) → 정의 대로 0 또는 1" do
      a = [3, 3, 3, 3]
      b = [3, 3, 3, 3]
      kappa = described_class.simple(a, b)
      expect(kappa).to be_within(1e-9).of(1.0)
    end
  end
end
