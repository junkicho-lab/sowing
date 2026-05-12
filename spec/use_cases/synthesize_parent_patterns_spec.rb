# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeParentPatterns do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-parent-patterns-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
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
    Sowing::Core::Settings.update(class_roster: [])
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  let(:seed_counter) { @seed_counter ||= [0] }

  def seed_consult(title:, body:, created_at:, mode: "record", category: "상담")
    seed_counter[0] += 1
    rid = "01PRT" + format("%021d", seed_counter[0])
    path = case mode
    when "memo" then "00_Inbox/#{rid}.md"
    when "note" then "20_Notes/#{category}/#{rid}.md"
    when "record" then "30_Records/#{Time.iso8601(created_at).year}/#{category}/#{rid}.md"
    end
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    File.write(abs, "---\nid: #{rid}\nmode: #{mode}\ncategory: #{category}\ntitle: #{title}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\n---\n\n#{body}\n")
    db[:entries].insert(
      id: rid, path: path, mode: mode, category: category, title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "0" * 16,
      word_count: body.split.size, indexed_at: created_at
    )
    rid
  end

  def seed_student_with_mentions(name:, entry_ids:)
    eid = db[:entities].insert(
      type: "student", name: name,
      first_seen_at: "2026-03-01T00:00:00+09:00",
      last_seen_at: "2026-07-31T00:00:00+09:00",
      mention_count: entry_ids.size
    )
    entry_ids.each { |id| db[:entity_mentions].insert(entity_id: eid, entry_id: id) }
    eid
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      mj1 = seed_consult(title: "민준 상담 1차", body: "민준 학부모 면담. 가정에서 책 읽기 시간 늘리기.",
        created_at: "2026-04-15T15:00:00+09:00")
      mj2 = seed_consult(title: "민준 상담 2차", body: "민준 어머니와 통화. 학습 동기 회복.",
        created_at: "2026-06-10T15:00:00+09:00")
      sy = seed_consult(title: "서연 상담", body: "서연 부모님 면담. 또래 관계 우려.",
        created_at: "2026-05-05T15:00:00+09:00")
      seed_consult(title: "5월 학부모 모임", body: "학부모 면담 일정 정리. 학년 행사 안내.",
        created_at: "2026-05-01T10:00:00+09:00", mode: "note", category: "meetings")

      seed_student_with_mentions(name: "민준", entry_ids: [mj1, mj2])
      seed_student_with_mentions(name: "서연", entry_ids: [sy])

      Sowing::Core::Settings.update(class_roster: %w[민준 서연 지호 수아])
    end

    it "Success — vault/.sowing/synth/parent-patterns/{semester}.md 작성" do
      result = use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      target = vault_dir.join(".sowing/synth/parent-patterns/2026-1.md")
      expect(target).to exist
    end

    it "frontmatter 11키 + synth_target=parent-patterns:2026-1 + 학생 카운트" do
      use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/parent-patterns/2026-1.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("parent-patterns:2026-1")
      expect(fm["synth_source_count"]).to eq(4)
      expect(fm["synth_consulted_count"]).to eq(2)  # 민준, 서연
      expect(fm["synth_roster_size"]).to eq(4)
      expect(fm["synth_unconsulted_count"]).to eq(2)  # 지호, 수아
      expect(fm["title"]).to include("학부모 상담 패턴")
    end

    it "본문 — 학생별 빈도 (민준 2회, 서연 1회) + 미상담 학생 명단" do
      use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/parent-patterns/2026-1.md").read
      ).content

      expect(body).to include("학생별 상담 빈도")
      expect(body).to include("**민준**: 2회")
      expect(body).to include("**서연**: 1회")
      expect(body).to include("아직 면담하지 않은 학생")
      expect(body).to include("- 지호")
      expect(body).to include("- 수아")
    end

    it "공통 토픽 키워드 추출 — 학부모 키워드는 STOPWORDS 로 제외" do
      use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/parent-patterns/2026-1.md").read
      ).content

      expect(body).to include("자주 등장한 주제 키워드")
      # "학부모", "면담", "상담" 은 STOPWORDS — 키워드 목록에 안 나와야 함
      keyword_section = body[/## 🔤[\s\S]*?(?=^## )/m]
      expect(keyword_section).not_to match(/`학부모`/)
      expect(keyword_section).not_to match(/`면담`/)
      expect(keyword_section).not_to match(/`상담`/)
    end

    it "trailer — 단정 거부 톤" do
      use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/parent-patterns/2026-1.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("원자료")
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:no_entries) — 매칭 < MIN_ENTRIES (2건)" do
      seed_consult(title: "x", body: "민준 면담", created_at: "2026-05-10T09:00:00+09:00")
      result = use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end

    it "Failure(:too_many_entries) — > MAX 가드" do
      stub_const("Sowing::UseCases::SynthesizeParentPatterns::MAX_ENTRIES", 2)
      4.times do |i|
        seed_consult(title: "x#{i}", body: "면담",
          created_at: "2026-05-#{format("%02d", i + 1)}T09:00:00+09:00")
      end
      result = use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_entries)
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
          "## 📊 학기 상담 흐름\n학기 상담 4건.\n\n## 🏠 가족 환경 패턴\n관찰 [#1].\n\n## 🎓 학습 환경 패턴\n학습 동기 [#2].\n\n## 💡 다음 학기 우선 면담 후보\n- 지호 검토\n"
        end

        def name
          "fake:parent-patterns"
        end
      }.new
    }

    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock)
    }

    before do
      seed_consult(title: "민준 상담", body: "민준 면담",
        created_at: "2026-04-15T15:00:00+09:00")
      seed_consult(title: "서연 상담", body: "서연 면담",
        created_at: "2026-05-05T15:00:00+09:00")
    end

    it "backend.chat 1회 + agent actor + LLM 본문 반영" do
      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end

      use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")

      expect(fake_backend.calls.size).to eq(1)
      expect(observed).to eq("agent")
      content = vault_dir.join(".sowing/synth/parent-patterns/2026-1.md").read
      expect(content).to include("다음 학기 우선 면담 후보")
    end

    it "LLM 실패 → 결정적 fallback" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "x")
      result = use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00", until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success
      content = vault_dir.join(".sowing/synth/parent-patterns/2026-1.md").read
      expect(content).to include("결정적 합성")
    end
  end
end
