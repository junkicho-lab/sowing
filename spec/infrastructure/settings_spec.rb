# frozen_string_literal: true

RSpec.describe Sowing::Core::Settings do
  before { described_class.reset! }
  after { described_class.reset! }

  describe ".load" do
    it "파일 없으면 DEFAULTS 반환" do
      settings = described_class.load
      expect(settings["onboarding_completed"]).to be false
      expect(settings["user_name"]).to be_nil
    end

    it "손상된 JSON은 DEFAULTS 폴백 (앱 부팅 막지 않음)" do
      File.write(described_class.path, "{ invalid json")
      expect { described_class.load }.not_to raise_error
      expect(described_class.load["onboarding_completed"]).to be false
    end
  end

  describe ".save / .update" do
    it "save로 신규 작성 + 다음 load에 반영" do
      described_class.save("user_name" => "김교사")
      expect(described_class.load["user_name"]).to eq("김교사")
    end

    it "update는 부분 갱신 (다른 키 보존)" do
      described_class.save("user_name" => "이름")
      described_class.update(onboarding_completed: true)

      settings = described_class.load
      expect(settings["user_name"]).to eq("이름")
      expect(settings["onboarding_completed"]).to be true
    end

    it "symbol 키도 처리 (string으로 정규화)" do
      described_class.update(user_name: "심볼키")
      expect(described_class.load["user_name"]).to eq("심볼키")
    end
  end

  describe ".onboarding_completed?" do
    it "기본값 false" do
      expect(described_class.onboarding_completed?).to be false
    end

    it "update 후 true" do
      described_class.update(onboarding_completed: true)
      expect(described_class.onboarding_completed?).to be true
    end
  end

  describe ".reset!" do
    it "파일 삭제 후 다시 DEFAULTS" do
      described_class.update(user_name: "삭제테스트")
      described_class.reset!
      expect(described_class.load["user_name"]).to be_nil
    end

    it "이미 없는 상태에서도 안전" do
      expect { described_class.reset! }.not_to raise_error
    end
  end
end
