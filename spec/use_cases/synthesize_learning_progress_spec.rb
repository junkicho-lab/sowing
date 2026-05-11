# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeLearningProgress do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-learn-progress-spec-")) }
  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:fixed_now) { Time.new(2026, 7, 31, 12, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }

  before do
    db[:entity_mentions].delete
    db[:entities].delete
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  let(:seed_counter) { @seed_counter ||= [0] }

  def seed_entry(title:, body:, created_at:, mode: "memo", category: nil)
    seed_counter[0] += 1
    rid = "01LRN" + format("%021d", seed_counter[0])
    path = case mode
    when "memo" then "00_Inbox/#{rid}.md"
    when "note" then "20_Notes/#{category || "lessons"}/#{rid}.md"
    when "record" then "30_Records/#{Time.iso8601(created_at).year}/#{category || "회고"}/#{rid}.md"
    end
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    fm = "id: #{rid}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\ntitle: #{title}"
    fm += "\ncategory: #{category}" if category
    File.write(abs, "---\n#{fm}\n---\n\n#{body}\n")
    db[:entries].insert(
      id: rid, path: path, mode: mode, category: category, title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "0" * 16,
      word_count: body.split.size, indexed_at: created_at
    )
    rid
  end

  describe "#call (결정적)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # "분수" 단원 6 차시 — 평균 7~10일 간격
      seed_entry(title: "분수 1차시 도입", body: "분수 도입.",
        created_at: "2026-05-01T09:00:00+09:00", mode: "note", category: "lessons")
      seed_entry(title: "분수 2차시", body: "분수 분할.",
        created_at: "2026-05-08T09:00:00+09:00", mode: "note", category: "lessons")
      seed_entry(title: "분수 3차시 통분", body: "분수 통분.",
        created_at: "2026-05-15T09:00:00+09:00", mode: "note", category: "lessons")
      seed_entry(title: "분수 평가", body: "분수 단원평가.",
        created_at: "2026-05-22T09:00:00+09:00", mode: "record", category: "평가")
      seed_entry(title: "분수 회고", body: "분수 단원 회고.",
        created_at: "2026-05-29T09:00:00+09:00", mode: "record", category: "수업회고")
      seed_entry(title: "분수 보충", body: "분수 보충 차시.",
        created_at: "2026-06-05T09:00:00+09:00", mode: "memo")
    end

    it "Success — vault/.sowing/synth/learning-progress/{keyword}.md" do
      result = use_case.call(keyword: "분수")
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/learning-progress/분수.md")).to exist
    end

    it "frontmatter — synth_keyword + status + avg_interval_days + days_since_last" do
      use_case.call(keyword: "분수")
      content = vault_dir.join(".sowing/synth/learning-progress/분수.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["synth_target"]).to eq("learning-progress:분수")
      expect(fm["synth_keyword"]).to eq("분수")
      expect(fm["synth_source_count"]).to eq(6)
      expect(fm["synth_avg_interval_days"]).to be_within(0.5).of(7.0)
      expect(fm["synth_status"]).to eq("ended")  # 6/5 → 7/31 = 56일 (ENDED 60일에 근접하지만 미만 → dormant)
        .or eq("dormant")
      expect(fm["synth_days_since_last"]).to be > 0
    end

    it "본문 — 진행 상태 / 페이스 / 활동 분포 / 누적 곡선 / timeline" do
      use_case.call(keyword: "분수")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/learning-progress/분수.md").read
      ).content

      expect(body).to include("진행 상태")
      expect(body).to include("페이스 분석")
      expect(body).to include("평균 차시 간격")
      expect(body).to include("학습 활동 분포")
      expect(body).to include("누적 차시 곡선")
      expect(body).to include("차시 timeline")
      expect(body).to include("분수 1차시")
    end

    it "trailer — 학생 능력 단정 거부 톤" do
      use_case.call(keyword: "분수")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/learning-progress/분수.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("학생 학습 부진")
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "invalid_keyword — 빈 문자열" do
      expect(use_case.call(keyword: "")).to be_failure
      expect(use_case.call(keyword: "   ").failure).to eq(:invalid_keyword)
    end

    it "no_entries — < MIN_ENTRIES (3건)" do
      seed_entry(title: "분수 1차시", body: "x", created_at: "2026-05-01T09:00:00+09:00")
      seed_entry(title: "분수 2차시", body: "x", created_at: "2026-05-08T09:00:00+09:00")
      result = use_case.call(keyword: "분수")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end
  end

  describe "#call (LLM 모드)" do
    let(:fake_backend) {
      Class.new {
        attr_reader :calls
        def initialize
          @calls = []
        end

        def chat(system:, user:)
          @calls << {system: system, user: user}
          "## 🎯 학습 페이스 평가\n일정한 페이스.\n\n## 📚 활동 균형 분석\n수업+평가+회고 균형.\n\n## 👥 학습 cohort 패턴\n관찰 후보.\n\n## 💡 다음 차시 우선순위 제안\n- 보충 검토.\n"
        end

        def name
          "fake:learning-progress"
        end
      }.new
    }

    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock)
    }

    before do
      3.times do |i|
        seed_entry(title: "분수 #{i + 1}차시", body: "분수 본문",
          created_at: "2026-05-#{format("%02d", (i + 1) * 7)}T09:00:00+09:00")
      end
    end

    it "backend.chat 1회 + agent actor + LLM 본문" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Infrastructure::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call(keyword: "분수")
      expect(fake_backend.calls.size).to eq(1)
      expect(observed).to eq("agent")
      content = vault_dir.join(".sowing/synth/learning-progress/분수.md").read
      expect(content).to include("학습 페이스 평가")
    end

    it "LLM 실패 → 결정적 fallback" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "x")
      result = use_case.call(keyword: "분수")
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/learning-progress/분수.md").read).to include("결정적 합성")
    end
  end
end
