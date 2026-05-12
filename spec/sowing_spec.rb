# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sowing do
  it "VERSION 상수가 정의되어 있다" do
    expect(Sowing::VERSION).to be_a(String)
  end

  it "환경이 test로 설정되어 있다" do
    expect(Sowing.env).to eq("test")
  end

  describe Sowing::Core::Paths do
    it "테스트 환경의 vault_dir 가 임시 디렉토리이다" do
      expect(described_class.vault_dir.to_s).to include("sowing-test-")
    end
  end
end
