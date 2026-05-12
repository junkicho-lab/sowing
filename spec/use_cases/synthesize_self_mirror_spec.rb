# frozen_string_literal: true

# Phase 13 W28-T01 — 17번째 합성기: 자기 거울 (5축).
RSpec.describe Sowing::UseCases::SynthesizeSelfMirror do
  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }
  let(:vault_repo) { Sowing::Repositories::VaultRepo.new(vault_dir: vault_dir) }
  let(:index_repo) { Sowing::Repositories::IndexRepo.new }
  let(:fixed_clock) {
    klass = Class.new do
      def self.now
        Time.new(2026, 5, 11, 14, 30, 0)
      end
    end
    klass
  }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    db[:entity_mentions].delete
    db[:entities].delete
    %w[00_Inbox 20_Notes 30_Records .sowing/synth].each do |d|
      FileUtils.rm_rf(vault_dir.join(d))
    end
  end

  # 시드: 특정 날짜·시간에 메모 N건
  def seed_memo(body, at: Time.new(2026, 5, 11, 14, 30, 0))
    Timecop.freeze(at) do
      Sowing::UseCases::CreateMemo.new(vault_repo: vault_repo, index_repo: index_repo)
        .call(body: body)
    end
  end

  describe "결정적 모드" do
    it ":daily entries 3건 미만 → Failure(:no_entries)" do
      seed_memo("오늘 1교시 활기찼다")
      seed_memo("도형 단원 시작")

      result = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :daily, date: "2026-05-11")
      expect(result.failure).to eq(:no_entries)
    end

    it ":daily 3건 이상 → Success + 마크다운 파일" do
      4.times { |i| seed_memo("협동학습 보람 활기 #{i}회 잘됐 #{i}", at: Time.new(2026, 5, 11, 9 + i, 0, 0)) }

      result = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :daily, date: "2026-05-11")
      expect(result.success?).to be true

      path = result.value!
      expect(path.to_s).to include(".sowing/synth/self-mirror/daily-2026-05-11.md")
      expect(File.exist?(path)).to be true
    end

    it "5축 섹션 모두 본문에 포함" do
      4.times { |i| seed_memo("협동학습 보람 #{i} 잘됐", at: Time.new(2026, 5, 11, 9 + i, 0, 0)) }

      path = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :daily, date: "2026-05-11").value!
      content = File.read(path)
      expect(content).to include("지성")
      expect(content).to include("감정")
      expect(content).to include("습관")
      expect(content).to include("관계")
      expect(content).to include("에너지")
    end

    it "frontmatter 에 synth_period + synth_period_date 기록" do
      4.times { |i| seed_memo("협동학습 #{i}", at: Time.new(2026, 5, 11, 9 + i, 0, 0)) }

      path = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :daily, date: "2026-05-11").value!
      content = File.read(path)
      expect(content).to include("synth_period: daily")
      expect(content).to include("synth_period_date: '2026-05-11'")
      expect(content).to include("synth_model: deterministic")
    end

    it "긍정 신호어 카운트 — '잘됐' '보람' '활기' 등 인식" do
      seed_memo("협동학습 너무 잘됐다 보람 있었어", at: Time.new(2026, 5, 11, 9, 0, 0))
      seed_memo("학생 발표 활기 있었다", at: Time.new(2026, 5, 11, 10, 0, 0))
      seed_memo("뿌듯한 하루였다", at: Time.new(2026, 5, 11, 11, 0, 0))

      path = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :daily, date: "2026-05-11").value!
      content = File.read(path)
      expect(content).to match(/긍정 신호어.*[1-9]/)
    end

    it "단정 거부 trailer 포함 (ADR-013)" do
      4.times { |i| seed_memo("협동 #{i}", at: Time.new(2026, 5, 11, 9 + i, 0, 0)) }

      path = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :daily, date: "2026-05-11").value!
      content = File.read(path)
      expect(content).to include("단정 거부")
      expect(content).to include("해석은 본인의 몫")
    end
  end

  describe ":weekly 모드" do
    it "이번 주 7일 entries 통합" do
      # 2026-W19 = 2026-05-04 ~ 2026-05-10
      Date.new(2026, 5, 4).upto(Date.new(2026, 5, 10)) do |d|
        seed_memo("협동학습 #{d}", at: Time.new(d.year, d.month, d.day, 10, 0, 0))
      end

      result = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :weekly, date: "2026-W19")
      expect(result.success?).to be true

      content = File.read(result.value!)
      expect(content).to include("자기 거울")
      expect(content).to include("이번 주")
    end

    it "weekly 파일명 weekly-{date}.md" do
      Date.new(2026, 5, 4).upto(Date.new(2026, 5, 10)) do |d|
        seed_memo("x #{d}", at: Time.new(d.year, d.month, d.day, 10, 0, 0))
      end

      path = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :weekly, date: "2026-W19").value!
      expect(path.basename.to_s).to eq("weekly-2026-W19.md")
    end
  end

  describe "잘못된 입력" do
    it ":invalid period → Failure(:invalid_period)" do
      result = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :hourly, date: "2026-05-11")
      expect(result.failure).to eq(:invalid_period)
    end

    it "date 미지정 → fixed_clock 기준 자동 생성" do
      4.times { |i| seed_memo("x #{i}", at: Time.new(2026, 5, 11, 9 + i, 0, 0)) }

      result = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :daily, date: nil)
      expect(result.success?).to be true
      expect(result.value!.basename.to_s).to eq("daily-2026-05-11.md")
    end
  end

  describe "LLM 모드 (mock backend)" do
    let(:mock_backend) do
      Class.new do
        def name; "Anthropic"; end

        def chat(system:, user:)
          "5축 종합: 협동학습 키워드가 두드러지고 긍정 신호가 지배적입니다. 다음 시도 후보로 학생 개별 관찰 메모를 권합니다."
        end
      end.new
    end

    it "LLM backend 주입 시 frontmatter synth_model: Anthropic" do
      4.times { |i| seed_memo("x #{i}", at: Time.new(2026, 5, 11, 9 + i, 0, 0)) }

      result = described_class.new(
        db: db, vault_dir: vault_dir, clock: fixed_clock, llm_backend: mock_backend
      ).call(period: :daily, date: "2026-05-11")
      expect(result.success?).to be true

      content = File.read(result.value!)
      expect(content).to include("synth_model: Anthropic")
      expect(content).to include("5축 종합 해석 (LLM)")
      expect(content).to include("협동학습 키워드가 두드러지고")
    end
  end

  describe "관계 (entity_mentions)" do
    it "학급 명단 entity 부재 시 비어있는 관계 섹션" do
      4.times { |i| seed_memo("x #{i}", at: Time.new(2026, 5, 11, 9 + i, 0, 0)) }

      path = described_class.new(db: db, vault_dir: vault_dir, clock: fixed_clock)
        .call(period: :daily, date: "2026-05-11").value!
      content = File.read(path)
      expect(content).to include("entity 부재")
    end
  end
end
