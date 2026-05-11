# frozen_string_literal: true

require "tmpdir"

RSpec.describe Sowing::Infrastructure::Dotenv do
  let(:tmp) { Dir.mktmpdir("sowing-dotenv-") }
  let(:test_keys) { %w[SOWING_DOTENV_TEST_A SOWING_DOTENV_TEST_B SOWING_DOTENV_TEST_QUOTED SOWING_DOTENV_TEST_HASH SOWING_DOTENV_EXPORT SOWING_DOTENV_EMPTY SOWING_DOTENV_OVERRIDE] }

  before { test_keys.each { |k| ENV.delete(k) } }
  after do
    test_keys.each { |k| ENV.delete(k) }
    FileUtils.remove_entry(tmp)
  end

  describe ".load" do
    it ".env 파일이 없으면 빈 배열 반환 + ENV 변경 없음" do
      expect(described_class.load(tmp)).to eq([])
    end

    it "기본 KEY=value 파싱" do
      File.write(File.join(tmp, ".env"), "SOWING_DOTENV_TEST_A=hello\n")
      described_class.load(tmp)
      expect(ENV["SOWING_DOTENV_TEST_A"]).to eq("hello")
    end

    it "큰따옴표·작은따옴표·공백 포함 값 처리" do
      File.write(File.join(tmp, ".env"), <<~ENV)
        SOWING_DOTENV_TEST_QUOTED="value with spaces"
        SOWING_DOTENV_TEST_B='single quoted'
      ENV
      described_class.load(tmp)
      expect(ENV["SOWING_DOTENV_TEST_QUOTED"]).to eq("value with spaces")
      expect(ENV["SOWING_DOTENV_TEST_B"]).to eq("single quoted")
    end

    it "주석 라인·인라인 주석·빈 라인 무시" do
      File.write(File.join(tmp, ".env"), <<~ENV)
        # 전체 주석
        SOWING_DOTENV_TEST_A=value # 인라인 주석

        SOWING_DOTENV_TEST_HASH="literal # not comment"
      ENV
      described_class.load(tmp)
      expect(ENV["SOWING_DOTENV_TEST_A"]).to eq("value")
      expect(ENV["SOWING_DOTENV_TEST_HASH"]).to eq("literal # not comment")
    end

    it "bash 스타일 'export KEY=value' 허용" do
      File.write(File.join(tmp, ".env"), "export SOWING_DOTENV_EXPORT=42\n")
      described_class.load(tmp)
      expect(ENV["SOWING_DOTENV_EXPORT"]).to eq("42")
    end

    it "빈 값 (KEY=) 은 빈 문자열로" do
      File.write(File.join(tmp, ".env"), "SOWING_DOTENV_EMPTY=\n")
      described_class.load(tmp)
      expect(ENV["SOWING_DOTENV_EMPTY"]).to eq("")
    end

    it "시스템 ENV 가 .env 보다 우선 — 절대 덮지 않음" do
      ENV["SOWING_DOTENV_OVERRIDE"] = "from-system"
      File.write(File.join(tmp, ".env"), "SOWING_DOTENV_OVERRIDE=from-dotenv\n")
      described_class.load(tmp)
      expect(ENV["SOWING_DOTENV_OVERRIDE"]).to eq("from-system")
    end

    it ".env.local 이 .env 보다 우선 (개인 비밀 ▶ 공통 기본값)" do
      File.write(File.join(tmp, ".env"), "SOWING_DOTENV_TEST_A=base\n")
      File.write(File.join(tmp, ".env.local"), "SOWING_DOTENV_TEST_A=personal\n")
      described_class.load(tmp)
      expect(ENV["SOWING_DOTENV_TEST_A"]).to eq("personal")
    end

    it "잘못된 키 이름 (숫자 시작·하이픈) 무시" do
      File.write(File.join(tmp, ".env"), <<~ENV)
        1BAD=ignored
        BAD-KEY=ignored
        SOWING_DOTENV_TEST_A=ok
      ENV
      described_class.load(tmp)
      expect(ENV["1BAD"]).to be_nil
      expect(ENV["BAD-KEY"]).to be_nil
      expect(ENV["SOWING_DOTENV_TEST_A"]).to eq("ok")
    end

    it "로딩한 파일 경로 배열 반환" do
      File.write(File.join(tmp, ".env"), "SOWING_DOTENV_TEST_A=v\n")
      File.write(File.join(tmp, ".env.local"), "SOWING_DOTENV_TEST_B=v\n")
      result = described_class.load(tmp)
      expect(result.size).to eq(2)
      expect(result.map { |p| File.basename(p) }).to contain_exactly(".env", ".env.local")
    end
  end
end
