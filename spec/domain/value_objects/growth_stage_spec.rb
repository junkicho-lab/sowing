# frozen_string_literal: true

RSpec.describe Sowing::Domain::ValueObjects::GrowthStage do
  describe "단계 매핑 (5단계)" do
    it "0건 → :empty" do
      stage = described_class.new(0)
      expect(stage.key).to eq(:empty)
      expect(stage.label).to include("시작")
    end

    it "1~9건 → :seed" do
      [1, 5, 9].each do |n|
        expect(described_class.new(n).key).to eq(:seed)
      end
    end

    it "10~49건 → :sprout" do
      [10, 25, 49].each do |n|
        expect(described_class.new(n).key).to eq(:sprout)
      end
    end

    it "50~149건 → :tree" do
      [50, 100, 149].each do |n|
        expect(described_class.new(n).key).to eq(:tree)
      end
    end

    it "150건+ → :forest" do
      [150, 500, 10_000].each do |n|
        expect(described_class.new(n).key).to eq(:forest)
      end
    end
  end

  describe "임계값 + 진행도" do
    it "다음 단계까지 남은 수" do
      expect(described_class.new(0).remaining_to_next).to eq(1)
      expect(described_class.new(7).remaining_to_next).to eq(3)
      expect(described_class.new(45).remaining_to_next).to eq(5)
      expect(described_class.new(149).remaining_to_next).to eq(1)
    end

    it "최종 단계(:forest)는 next_threshold/remaining nil" do
      stage = described_class.new(200)
      expect(stage.next_threshold).to be_nil
      expect(stage.remaining_to_next).to be_nil
      expect(stage.progress_ratio).to eq(1.0)
    end

    it "progress_ratio는 현재 단계 시작점 대비 다음 단계까지의 비율" do
      # seed: 1 (시작) → sprout 10 (다음). 5건이면 (5-1)/(10-1) = 4/9 ≈ 0.44
      ratio = described_class.new(5).progress_ratio
      expect(ratio).to be_within(0.01).of(0.44)
    end
  end

  describe "검증" do
    it "음수는 거부" do
      expect { described_class.new(-1) }.to raise_error(ArgumentError)
    end
  end

  describe "메시지 표시" do
    it "각 단계마다 격려 메시지가 다름" do
      messages = [0, 1, 10, 50, 150].map { |n| described_class.new(n).message }
      expect(messages.uniq.size).to eq(5)
    end
  end
end
