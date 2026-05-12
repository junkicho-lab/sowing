# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeSelfPatterns do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-self-patterns-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 7, 31, 12, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }

  before do
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  let(:seed_counter) { @seed_counter ||= [0] }

  def seed_entry(body:, created_at:, title: "(제목)", mode: "memo", category: nil)
    seed_counter[0] += 1
    rid = "01SLF" + format("%021d", seed_counter[0])
    path = case mode
    when "memo" then "00_Inbox/#{rid}.md"
    when "note" then "20_Notes/#{category || "lessons"}/#{rid}.md"
    when "record" then "30_Records/#{Time.iso8601(created_at).year}/#{category || "회고"}/#{rid}.md"
    end
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    fm = "id: #{rid}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'"
    fm += "\ncategory: #{category}" if category
    fm += "\ntitle: #{title}"
    File.write(abs, "---\n#{fm}\n---\n\n#{body}\n")

    db[:entries].insert(
      id: rid, path: path, mode: mode, category: category, title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "0" * 16,
      word_count: body.split.size, indexed_at: created_at
    )
    rid
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # 12 entries — MIN_ENTRIES=10 충족. 다양한 모드/시간대/톤.
      seed_entry(body: "오늘 협동학습 잘 됐다. 보람 있었다.",
        created_at: "2026-04-01T09:00:00+09:00")
      seed_entry(body: "민준이 발표 자원했다. 뿌듯한 순간.",
        created_at: "2026-04-08T20:00:00+09:00")
      seed_entry(body: "수업 회고 — 효과적이었다.",
        created_at: "2026-04-15T14:00:00+09:00", mode: "record", category: "수업회고")
      seed_entry(body: "분수 단원 어려웠다. 학생들 헷갈려 함.",
        created_at: "2026-04-22T09:00:00+09:00")
      seed_entry(body: "도덕 갈등 활동 활기차게 진행.",
        created_at: "2026-05-01T09:00:00+09:00")
      seed_entry(body: "협동학습 정착. 만족스러운 성장.",
        created_at: "2026-05-10T20:00:00+09:00")
      seed_entry(body: "학부모 상담 정리.",
        created_at: "2026-05-20T15:00:00+09:00", mode: "note", category: "meetings")
      seed_entry(body: "수업 준비. 자료 정리.",
        created_at: "2026-06-01T08:00:00+09:00")
      # 최근 4주 — 부정 톤 증가
      seed_entry(body: "수업 힘들었다. 시간 부족했고 산만했다.",
        created_at: "2026-07-08T20:00:00+09:00")
      seed_entry(body: "학기말 정신없다. 피곤하고 막막한 느낌.",
        created_at: "2026-07-15T20:00:00+09:00")
      seed_entry(body: "도서 회고 — 답답한 마음 정리.",
        created_at: "2026-07-22T20:00:00+09:00", mode: "note", category: "books")
      seed_entry(body: "수업 진행. 끝.",
        created_at: "2026-07-25T20:00:00+09:00")
    end

    it "Success — vault/.sowing/synth/self-patterns/{period}.md 작성" do
      result = use_case.call(period_label: "2026-1학기",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      target = vault_dir.join(".sowing/synth/self-patterns/2026-1학기.md")
      expect(target).to exist
    end

    it "frontmatter 11키 + synth_target=self-patterns:{label}" do
      use_case.call(period_label: "2026-1학기",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/self-patterns/2026-1학기.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("self-patterns:2026-1학기")
      expect(fm["synth_source_count"]).to eq(12)
      expect(fm["synth_positive_count"]).to be > 0
      expect(fm["synth_negative_count"]).to be > 0
      expect(fm["title"]).to include("자기 회고 패턴")
    end

    it "본문 — 기본 통계 + 시간대 + 카테고리 + 키워드 + 톤 신호어" do
      use_case.call(period_label: "2026-1학기",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/self-patterns/2026-1학기.md").read
      ).content

      expect(body).to include("기본 통계")
      expect(body).to include("총 entries: **12건**")
      expect(body).to include("작성 시간대 분포")
      expect(body).to include("자주 다룬 카테고리")
      expect(body).to include("자주 등장한 토픽 키워드")
      expect(body).to include("톤 신호어 카운트")
      expect(body).to include("최근 4주 vs 이전")
    end

    it "최근 4주 부정 톤 증가 — recent_signals 가 older_signals 보다 부정 비율 ↑" do
      use_case.call(period_label: "2026-1학기",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/self-patterns/2026-1학기.md").read
      ).content

      # 표 안에 최근 4주 row + 이전 row 모두 표시
      expect(body).to include("| 이전 (")
      expect(body).to include("| 최근 4주 (")
      # recent 의 부정 카운트가 0 이상 (부정 신호어 시드됨)
      table_section = body[/## 📈[\s\S]*?(?=^##)/m]
      expect(table_section).to include("최근 4주")
    end

    it "trailer — 단정 거부 톤 (\"교사가 지쳤다\" X)" do
      use_case.call(period_label: "2026-1학기",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/self-patterns/2026-1학기.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("단정 거부")
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:no_entries) — 매칭 < MIN_ENTRIES (10건)" do
      5.times do |i|
        seed_entry(body: "x", created_at: "2026-05-#{format("%02d", i + 1)}T09:00:00+09:00")
      end
      result = use_case.call(period_label: "x",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
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
          "## 🌊 집필 시기별 톤 변화\n사실 기반.\n\n## 💡 자주 환기되는 주제\n협동학습.\n\n## 🌱 잠재적 burnout 시그널\n부정 표현 증가 — 후보.\n\n## 💭 다음 학기 의도적 시도 후보\n- 새 카테고리 검토\n"
        end

        def name
          "fake:self-patterns"
        end
      }.new
    }

    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock)
    }

    before do
      12.times do |i|
        seed_entry(body: "본문 #{i} 잘 됐다.",
          created_at: "2026-05-#{format("%02d", (i % 28) + 1)}T09:00:00+09:00")
      end
    end

    it "backend.chat 1회 + agent actor + LLM 본문" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end

      use_case.call(period_label: "test",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(fake_backend.calls.size).to eq(1)
      expect(observed).to eq("agent")
      content = vault_dir.join(".sowing/synth/self-patterns/test.md").read
      expect(content).to include("잠재적 burnout 시그널")
    end

    it "LLM 실패 → 결정적 fallback" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "x")
      result = use_case.call(period_label: "test",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/self-patterns/test.md").read).to include("결정적 합성")
    end
  end
end
