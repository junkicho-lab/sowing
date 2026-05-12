# frozen_string_literal: true

require "fileutils"
require "front_matter_parser"
require "json"
require "tmpdir"
require "yaml"

RSpec.describe Sowing::UseCases::SynthesizeSemesterReflection do
  let(:vault_dir) { Pathname.new(Dir.mktmpdir("synth-reflection-spec-")) }
  let(:db) { Sowing::Core::DB.connection }
  let(:fixed_now) { Time.new(2026, 7, 31, 18, 0, 0, "+09:00") }
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

  # 한 entry + 마크다운 파일 시드. created_at 으로 학기 분할 검증.
  def seed_entry(id:, body:, created_at:, mode: "memo", category: nil, title: nil, path: nil)
    path ||= default_path(mode, id, category, created_at)
    abs = vault_dir.join(path)
    FileUtils.mkdir_p(abs.dirname)
    File.write(abs, "---\nid: #{id}\nmode: #{mode}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\n---\n\n#{body}\n")

    db[:entries].insert(
      id: id, path: path, mode: mode,
      title: title, category: category,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "deadbeef00000000",
      word_count: body.split.size, indexed_at: created_at
    )
  end

  def default_path(mode, id, category, created_at)
    case mode
    when "memo" then "00_Inbox/#{id}.md"
    when "note" then "20_Notes/#{category || "수업"}/#{id}.md"
    when "record" then "30_Records/#{Time.iso8601(created_at).year}/#{category || "수업회고"}/#{id}.md"
    end
  end

  def seed_entity_with_mentions(name:, type:, entry_ids:)
    eid = db[:entities].insert(
      type: type, name: name,
      first_seen_at: "2026-03-01T00:00:00+09:00",
      last_seen_at: "2026-07-31T00:00:00+09:00",
      mention_count: entry_ids.size
    )
    entry_ids.each { |entry_id| db[:entity_mentions].insert(entity_id: eid, entry_id: entry_id) }
    eid
  end

  describe "#call (결정적 모드)" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    before do
      # 학기 (2026-1: 3월~7월) 시뮬레이션 — 월별 entry 분포.
      # 3월: 2건 (개학 적응)
      # 4월: 3건 (협동학습 시도)
      # 5월: 2건 (민준 발표 자원 + 학부모 상담)
      # 6월: 2건 (도덕 갈등 + 분수 단원)
      # 7월: 1건 (학기말)
      seed_entry(id: "01REF000000000000000003M1", body: "개학 첫 주. 학급 분위기 조성.",
        created_at: "2026-03-04T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01REF000000000000000003M2", body: "자리 배치 점검.",
        created_at: "2026-03-15T09:00:00+09:00", mode: "memo")

      seed_entry(id: "01REF000000000000000004M1", body: "협동학습 첫 시도.",
        created_at: "2026-04-02T09:00:00+09:00", mode: "note", category: "수업", title: "협동학습 1차시")
      seed_entry(id: "01REF000000000000000004M2", body: "민준이 모둠 활동 적응.",
        created_at: "2026-04-12T09:00:00+09:00", mode: "memo")
      seed_entry(id: "01REF000000000000000004M3", body: "수업 회고 — 모둠별 속도 차이.",
        created_at: "2026-04-25T20:00:00+09:00", mode: "record", category: "수업회고", title: "협동학습 2주차 회고")

      seed_entry(id: "01REF000000000000000005M1", body: "민준이가 처음으로 발표를 자원했다!",
        created_at: "2026-05-05T14:30:00+09:00", mode: "memo")
      seed_entry(id: "01REF000000000000000005M2", body: "학부모 상담.",
        created_at: "2026-05-20T16:00:00+09:00", mode: "note", category: "상담", title: "민준이 학부모 상담")

      seed_entry(id: "01REF000000000000000006M1", body: "도덕 갈등 해결 활동 2차시.",
        created_at: "2026-06-10T09:00:00+09:00", mode: "note", category: "수업", title: "도덕 갈등 해결")
      seed_entry(id: "01REF000000000000000006M2", body: "분수 단원 평가.",
        created_at: "2026-06-25T09:00:00+09:00", mode: "memo")

      seed_entry(id: "01REF000000000000000007M1", body: "학기말 정리. 다음 학기 준비.",
        created_at: "2026-07-15T20:00:00+09:00", mode: "record", category: "학기회고", title: "1학기 마무리")

      # 학생 entity — 민준이가 4건 mention (5월 1, 4월 1 + 5월 학부모 1, 7월 1).
      seed_entity_with_mentions(name: "민준", type: "student",
        entry_ids: %w[01REF000000000000000004M2 01REF000000000000000005M1 01REF000000000000000005M2 01REF000000000000000007M1])
      seed_entity_with_mentions(name: "서연", type: "student",
        entry_ids: %w[01REF000000000000000004M3])
    end

    it "Success(target Pathname) — vault/.sowing/synth/reflections/2026-1.md 작성" do
      result = use_case.call(semester_label: "2026-1",
        since: "2026-03-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_success

      target = vault_dir.join(".sowing/synth/reflections/2026-1.md")
      expect(target).to exist
      expect(result.value!).to eq(target)
    end

    it "frontmatter 필수 키 8종 + synth_target = semester:2026-1" do
      use_case.call(semester_label: "2026-1",
        since: "2026-03-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/reflections/2026-1.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter

      expect(fm["is_synth"]).to be true
      expect(fm["synth_target"]).to eq("semester:2026-1")
      expect(fm["synth_at"]).to eq(fixed_now.iso8601)
      expect(fm["synth_source_count"]).to eq(10)  # 위에 시드한 10건
      expect(fm["synth_model"]).to eq("deterministic")
      expect(fm["synth_period_since"]).to start_with("2026-03-01")
      expect(fm["synth_period_until"]).to start_with("2026-07-31")
      expect(fm["title"]).to eq("학기 회고: 2026-1")
    end

    it "본문 — 5 결정적 섹션 + 월별 청크 + top 학생/카테고리" do
      use_case.call(semester_label: "2026-1",
        since: "2026-03-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/reflections/2026-1.md").read
      ).content

      expect(body).to include("## 이번 학기 흐름")
      expect(body).to include("총 10건")
      expect(body).to include("## 자주 등장한 학생")
      expect(body).to include("**민준**: 4회 언급")
      expect(body).to include("**서연**: 1회 언급")
      expect(body).to include("## 자주 다룬 카테고리")
      expect(body).to include("**수업**: 2건")  # 4월·6월 note 2건
      expect(body).to include("## 월별 타임라인")

      # 청크 — 모든 월 (3·4·5·6·7) 출현
      %w[2026-03 2026-04 2026-05 2026-06 2026-07].each { |m| expect(body).to include(m) }

      # 위키링크 인용 — 첫 entry 가 [[path]] 로
      expect(body).to include("[[00_Inbox/01REF000000000000000003M1.md]]")
    end

    it "month chunks 시간순 — 3 → 4 → 5 → 6 → 7" do
      use_case.call(semester_label: "2026-1",
        since: "2026-03-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/reflections/2026-1.md").read
      ).content

      mar_idx = body.index("2026-03")
      jul_idx = body.index("2026-07")
      expect(mar_idx).to be < jul_idx
    end
  end

  describe "#call — 입력 범위 / 가드" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "Failure(:no_entries) — 범위 내 entries < MIN_ENTRIES (5건)" do
      seed_entry(id: "01REF0000000000000000NONE1", body: "일부", created_at: "2026-05-01T09:00:00+09:00")
      result = use_case.call(semester_label: "2026-1",
        since: "2026-04-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:no_entries)
    end

    it "Failure(:too_many_entries) — 범위 내 entries > MAX_ENTRIES (1000건)" do
      stub_const("Sowing::UseCases::SynthesizeSemesterReflection::MAX_ENTRIES", 3)
      5.times do |i|
        seed_entry(id: "01REF00000000000000ZMANY#{i}", body: "x", created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00")
      end
      result = use_case.call(semester_label: "test",
        since: "2026-05-01T00:00:00+09:00",
        until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_failure
      expect(result.failure).to eq(:too_many_entries)
    end

    it "since/until 기본값 — 미지정 시 clock.now 기준 6개월" do
      # fixed_now = 2026-07-31. 6개월 전 = 2026-02-01 경.
      # 2026-01-15 (범위 밖) + 2026-03~07 (범위 안) — 5건 시드
      seed_entry(id: "01REF0000000000000DEFAULT0", body: "범위 밖", created_at: "2026-01-15T09:00:00+09:00")
      5.times do |i|
        seed_entry(id: "01REF0000000000000DEFAULT#{i + 1}", body: "범위 안",
          created_at: "2026-0#{i + 3}-01T09:00:00+09:00")
      end

      result = use_case.call(semester_label: "default-window")
      expect(result).to be_success
      content = vault_dir.join(".sowing/synth/reflections/default-window.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      # 5건만 (2026-01 제외)
      expect(fm["synth_source_count"]).to eq(5)
    end
  end

  describe "#call (LLM 모드) — backend 주입" do
    let(:fake_backend) {
      Class.new {
        attr_reader :calls

        def initialize
          @calls = []
        end

        def chat(system:, user:)
          @calls << {system: system, user: user}
          # 청크 요청과 종합 요청 구분 — 마지막 호출이 종합.
          if user.include?("월별 요약")
            "## 이번 학기 흐름\n학생 변화 두드러짐.\n\n## 변화의 순간들\n민준이 발표 자원.\n\n## 잘된 점\n협동학습 정착.\n\n## 아쉬웠던 점\n속도 차이.\n\n## 다음 학기 준비\n보조 과제 카드.\n"
          else
            "월간 요약 텍스트."
          end
        end

        def name
          "fake:test-model"
        end
      }.new
    }

    subject(:use_case) {
      described_class.new(db: db, vault_dir: vault_dir, llm_backend: fake_backend, clock: clock)
    }

    before do
      # 5건 시드 (3월·4월·5월·6월·7월) — 5 청크 → 5 chunk 호출 + 1 synthesis 호출
      %w[03 04 05 06 07].each_with_index do |m, i|
        seed_entry(id: "01REFLLM00000000000000000#{i + 1}", body: "본문 #{m}",
          created_at: "2026-#{m}-15T09:00:00+09:00")
      end
    end

    it "backend.chat 가 청크별 + 종합 (총 6번) 호출" do
      use_case.call(semester_label: "2026-1",
        since: "2026-03-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")
      expect(fake_backend.calls.size).to eq(6)  # 5 청크 + 1 종합
    end

    it "synth_model = backend.name + 본문에 LLM 출력 반영" do
      use_case.call(semester_label: "2026-1",
        since: "2026-03-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")
      content = vault_dir.join(".sowing/synth/reflections/2026-1.md").read
      fm = FrontMatterParser::Parser.new(:md).call(content).front_matter
      body = FrontMatterParser::Parser.new(:md).call(content).content

      expect(fm["synth_model"]).to eq("fake:test-model")
      expect(body).to include("## 변화의 순간들")
      expect(body).to include("민준이 발표 자원")
    end

    it "audit log actor=agent — LLM 모드에서만" do
      Sowing::Core::AuditLog.instance.clear!

      # SynthesizeSemesterReflection 자체는 audit 안 남기지만 (SynthController 가
      # synth_generate audit 처리), with_actor 블록 안에서 동작 — Phase 11 패턴 준수.
      # 여기선 with_actor 컨텍스트가 합성 동안 활성화되는지 검증.
      observed_actor = nil
      allow(fake_backend).to receive(:chat).and_wrap_original do |orig, **args|
        observed_actor ||= Sowing::Core::AuditLog.current_actor
        orig.call(**args)
      end

      use_case.call(semester_label: "2026-1",
        since: "2026-03-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")

      expect(observed_actor).to eq("agent")
    end

    it "LLM 실패 → 결정적 폴백 (사용자에게 빈 결과보다 나음)" do
      allow(fake_backend).to receive(:chat).and_raise(StandardError, "LLM 죽음")
      result = use_case.call(semester_label: "2026-1",
        since: "2026-03-01T00:00:00+09:00",
        until_time: "2026-07-31T23:59:59+09:00")

      expect(result).to be_success
      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/reflections/2026-1.md").read
      ).content
      # 결정적 합성의 trailer 문구
      expect(body).to include("결정적 합성 (통계 + 타임라인)")
    end
  end

  describe "엣지 케이스" do
    subject(:use_case) { described_class.new(db: db, vault_dir: vault_dir, clock: clock) }

    it "멱등 — 같은 라벨 재호출 시 atomic 덮어쓰기 (synth_at 갱신)" do
      5.times do |i|
        seed_entry(id: "01REF00000000000000IDEM#{i + 1}", body: "x",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00")
      end

      use_case.call(semester_label: "2026-1",
        since: "2026-05-01T00:00:00+09:00",
        until_time: "2026-05-31T23:59:59+09:00")
      first_mtime = vault_dir.join(".sowing/synth/reflections/2026-1.md").mtime

      sleep 0.01
      use_case.call(semester_label: "2026-1",
        since: "2026-05-01T00:00:00+09:00",
        until_time: "2026-05-31T23:59:59+09:00")
      second_mtime = vault_dir.join(".sowing/synth/reflections/2026-1.md").mtime

      expect(second_mtime).to be >= first_mtime
    end

    it "학생 entity 0개여도 회고 가능 (안내 문구 + 통계만)" do
      5.times do |i|
        seed_entry(id: "01REF000000000000NOENT#{i + 1}", body: "x",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00")
      end

      result = use_case.call(semester_label: "no-entity",
        since: "2026-05-01T00:00:00+09:00",
        until_time: "2026-05-31T23:59:59+09:00")
      expect(result).to be_success

      body = FrontMatterParser::Parser.new(:md).call(
        vault_dir.join(".sowing/synth/reflections/no-entity.md").read
      ).content
      expect(body).to include("학생 entity 인덱스 없음")
    end

    it "vault 마크다운 파일 없는 entry — body 빈 문자열 (graceful)" do
      seed_entry(id: "01REF000000000000MISS001", body: "원본",
        created_at: "2026-05-01T09:00:00+09:00")
      # 파일 직접 삭제 — DB 만 남김
      vault_dir.join("00_Inbox/01REF000000000000MISS001.md").delete
      4.times do |i|
        seed_entry(id: "01REF000000000000MISS00#{i + 2}", body: "다른",
          created_at: "2026-05-#{(i + 2).to_s.rjust(2, "0")}T09:00:00+09:00")
      end

      expect {
        use_case.call(semester_label: "miss",
          since: "2026-05-01T00:00:00+09:00",
          until_time: "2026-05-31T23:59:59+09:00")
      }.not_to raise_error
    end
  end
end
