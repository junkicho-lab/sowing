# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeTagClusters do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-clusters-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 7, 31, 18, 0, 0, "+09:00") }
  let(:clock) { class_double(Time, now: fixed_now) }

  before do
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete
  end

  after { FileUtils.rm_rf(vault_dir) if vault_dir.exist? }

  def seed_entry(id:, body: "x", mode: "memo", title: nil, tags: [], created_at: "2026-05-01T09:00:00+09:00")
    path = "00_Inbox/#{id}.md"
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    fm = "id: #{id}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'"
    fm += "\ntitle: #{title}" if title
    File.write(abs, "---\n#{fm}\n---\n\n#{body}\n")
    db[:entries].insert(
      id: id, path: path, mode: mode, title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: 1, indexed_at: created_at
    )
    tags.each do |tag_name|
      tid = db[:tags].where(name: tag_name).first&.dig(:id) ||
        db[:tags].insert(name: tag_name)
      db[:entry_tags].insert(entry_id: id, tag_id: tid)
    end
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # 클러스터 1: 협동학습 + 모둠 (3건 함께 등장)
      seed_entry(id: "01TGC000000000000000A001", tags: %w[협동학습 모둠])
      seed_entry(id: "01TGC000000000000000A002", tags: %w[협동학습 모둠])
      seed_entry(id: "01TGC000000000000000A003", tags: %w[협동학습 모둠 갈등])
      # 클러스터 2: 평가 + 분수 (2건 함께)
      seed_entry(id: "01TGC000000000000000B001", tags: %w[평가 분수])
      seed_entry(id: "01TGC000000000000000B002", tags: %w[평가 분수])
      # 단독 태그 (빈도 1) — 후보 제외
      seed_entry(id: "01TGC000000000000000C001", tags: %w[단독])
      # 빈도 충분하지만 다른 태그와 co-occurrence 없음 (제외)
      seed_entry(id: "01TGC000000000000000D001", tags: %w[독립])
      seed_entry(id: "01TGC000000000000000D002", tags: %w[독립])
    end

    it "Success(target Pathname) — vault/.sowing/synth/tag-clusters/topics.md" do
      result = use_case.call
      expect(result).to be_success
      expect(vault_dir.join(".sowing/synth/tag-clusters/topics.md")).to exist
    end

    it "frontmatter — synth_target=clusters:topics + jaccard threshold + 클러스터된 태그 목록" do
      use_case.call
      fm = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/tag-clusters/topics.md").read
      ).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("clusters:topics")
      expect(fm["synth_jaccard_threshold"]).to eq(0.3)
      expect(fm["synth_clustered_tags"]).to include("협동학습", "모둠", "평가", "분수")
      expect(fm["synth_clustered_tags"]).not_to include("단독")  # 빈도 1
      expect(fm["title"]).to eq("태그 클러스터: 주제 그룹")
    end

    it "본문 — 2 클러스터 (협동학습-모둠 그룹 + 평가-분수 그룹)" do
      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/tag-clusters/topics.md").read
      ).content

      expect(body).to include("🏷️ 태그 클러스터")
      expect(body).to include("#협동학습")
      expect(body).to include("#모둠")
      expect(body).to include("#평가")
      expect(body).to include("#분수")
      # 단독은 클러스터링 안 됨
      expect(body).not_to include("#단독")
      # 대표 entries
      expect(body).to include("[[00_Inbox/01TGC000000000000000A001.md]]")
    end

    it "결정적 trailer — 단정 거부 톤" do
      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/tag-clusters/topics.md").read
      ).content
      expect(body).to include("결정적 합성")
      expect(body).to include("Jaccard")
    end
  end

  describe "#call — 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:no_tags) — 빈도 ≥ MIN_TAG_FREQ 인 태그가 2개 미만" do
      seed_entry(id: "01TGCNT00000000000000A1", tags: %w[하나만])
      result = use_case.call
      expect(result).to be_failure
      expect(result.failure).to eq(:no_tags)
    end

    it "Failure(:no_clusters) — 빈도 충분하지만 jaccard 임계 미달" do
      # 두 태그 모두 빈도 2 인데 같이 등장 안 함 → jaccard = 0
      seed_entry(id: "01TGCNC00000000000000A1", tags: %w[A])
      seed_entry(id: "01TGCNC00000000000000A2", tags: %w[A])
      seed_entry(id: "01TGCNC00000000000000B1", tags: %w[B])
      seed_entry(id: "01TGCNC00000000000000B2", tags: %w[B])

      result = use_case.call
      expect(result).to be_failure
      expect(result.failure).to eq(:no_clusters)
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
          "### [1] 협동학습 (제안)\n- **태그**: #협동학습 #모둠\n- **주제**: 모둠 협력 패턴\n- **자기 발견 질문**: 무엇이 효과적이었나?\n\n## 💡 메타-관찰\n협동학습 누적이 두드러짐.\n"
        end

        def name
          "fake:tag-clusters"
        end
      }.new
    }

    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock) }

    before do
      seed_entry(id: "01TGCLLM0000000000000A1", tags: %w[협동학습 모둠])
      seed_entry(id: "01TGCLLM0000000000000A2", tags: %w[협동학습 모둠])
    end

    it "backend.chat 1회 + 본문 + agent actor + 실패 fallback" do
      use_case.call
      expect(fake_backend.calls.size).to eq(1)
      content = vault_dir.join(".sowing/synth/tag-clusters/topics.md").read
      expect(content).to include("💡 메타-관찰")

      observed = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end
      use_case.call
      expect(observed).to eq("agent")

      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call
      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/tag-clusters/topics.md").read
      ).content
      expect(body).to include("결정적 합성")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "멱등 — 재호출 atomic 덮어쓰기" do
      2.times do |i|
        seed_entry(id: "01TGCIDM0000000000000A#{i + 1}", tags: %w[협동학습 모둠])
      end
      use_case.call
      first = vault_dir.join(".sowing/synth/tag-clusters/topics.md").mtime
      sleep 0.01
      use_case.call
      second = vault_dir.join(".sowing/synth/tag-clusters/topics.md").mtime
      expect(second).to be >= first
    end

    it "큰 클러스터 (3개 이상 태그) — union-find 로 묶임" do
      # 협동학습 + 모둠 + 갈등 모두 함께 등장 → 하나의 클러스터
      4.times do |i|
        seed_entry(id: "01TGCBIG0000000000000A#{i + 1}", tags: %w[협동학습 모둠 갈등])
      end

      use_case.call
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/tag-clusters/topics.md").read
      ).content
      # 한 그룹에 3 태그 모두 들어감
      expect(body).to match(/3개 태그 그룹/)
    end
  end
end
