# frozen_string_literal: true

require "rack/test"
require "fileutils"
require "json"

RSpec.describe "통합 /synth 대시보드 (W21-T04)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }
  let(:synth_root) { vault_dir.join(".sowing/synth") }
  let(:audit_log) { Sowing::Infrastructure::AuditLog.instance }

  def app
    Sowing::Application
  end

  def esc(s)
    Rack::Utils.escape(s)
  end

  # 4 type 의 합성 파일을 직접 시드 — 실제 합성기와 같은 frontmatter 형식.
  def seed_synth(type, slug, fm_extra = {})
    dir = synth_root.join(type)
    FileUtils.mkdir_p(dir)
    fm = {
      "is_synth" => true,
      "synth_at" => Time.now.iso8601,
      "synth_source_count" => 3,
      "synth_model" => "deterministic",
      "title" => "Test #{type} #{slug}"
    }.merge(fm_extra)
    yaml = YAML.dump(fm).delete_prefix("---\n")
    File.write(dir.join("#{slug}.md"), "---\n#{yaml}---\n\n# Test\n\n본문 내용.\n")
  end

  before do
    header "Host", "127.0.0.1"
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    db[:entity_mentions].delete
    db[:entities].delete
    %w[00_Inbox 20_Notes 30_Records .sowing/synth .sowing/trash].each do |d|
      FileUtils.rm_rf(vault_dir.join(d))
    end
    audit_log.clear!
  end

  describe "GET /synth — 통합 대시보드" do
    it "4 type 모두 빈 상태 — 안내 + 4 type 섹션 모두 표시 + 생성 폼" do
      get "/synth"
      expect(last_response).to be_ok
      expect(last_response.body).to include("검토 대기 중인 합성 결과가 없습니다")
      # 4 섹션 라벨 모두 표시
      expect(last_response.body).to include("학생 디제스트")
      expect(last_response.body).to include("학기 회고")
      expect(last_response.body).to include("수업 패턴 후보")
      expect(last_response.body).to include("학생 묘사 변화")
      # 4 생성 폼 action URL
      expect(last_response.body).to include("/synth/reflections/generate")
      expect(last_response.body).to include("/synth/patterns/lessons/generate")
      expect(last_response.body).to include("/synth/contradictions/observations/generate")
    end

    it "4 type 모두 시드 시 각 섹션에 카드 표시 + accept/reject 버튼" do
      seed_synth("students", "민준", "synth_target" => "student:민준")
      seed_synth("reflections", "2026-1", "synth_target" => "semester:2026-1")
      seed_synth("patterns", "lessons", "synth_target" => "patterns:lessons")
      seed_synth("contradictions", "observations", "synth_target" => "contradictions:observations")

      get "/synth"
      expect(last_response).to be_ok
      # 카드 4개 모두 등장
      expect(last_response.body).to include("Test students 민준")
      expect(last_response.body).to include("Test reflections 2026-1")
      expect(last_response.body).to include("Test patterns lessons")
      expect(last_response.body).to include("Test contradictions observations")
      # accept/reject 버튼 4 type
      expect(last_response.body).to include("/synth/students/민준/accept")
      expect(last_response.body).to include("/synth/reflections/2026-1/accept")
      expect(last_response.body).to include("/synth/patterns/lessons/accept")
      expect(last_response.body).to include("/synth/contradictions/observations/accept")
    end

    it "'이번 주 새로 합성' 배지 — 7일 이내 synth_at" do
      seed_synth("students", "최근", "synth_at" => (Time.now - 3 * 86_400).iso8601)
      seed_synth("students", "오래됨", "synth_at" => (Time.now - 30 * 86_400).iso8601)

      get "/synth"
      body = last_response.body

      # 배지는 정확히 1번만 등장 (최근 카드만)
      expect(body.scan("이번 주 새로 합성").size).to eq(1)

      # 카드별로 분리해서 — 각 카드 영역에 배지 유무 확인
      cards = body.scan(/<li class="synth-card">[\s\S]*?<\/li>/)
      recent_card = cards.find { |c| c.include?("최근") }
      old_card = cards.find { |c| c.include?("오래됨") }

      expect(recent_card).to include("이번 주 새로 합성")
      expect(old_card).not_to include("이번 주 새로 합성")
    end

    it "type별 섹션 — open 상태는 items 가 있을 때만" do
      seed_synth("students", "민준", "synth_target" => "student:민준")
      get "/synth"
      # students 섹션은 open
      students_section = last_response.body[/<details[^>]*?>.*?학생 디제스트.*?<\/details>/m]
      expect(students_section).to include("open")
    end
  end

  describe "GET /synth/:type/:slug — 통합 상세" do
    it "reflections 상세 — type 배지 + 메타 + 수락/거절 (재생성 버튼 X)" do
      seed_synth("reflections", "2026-1",
        "synth_target" => "semester:2026-1",
        "synth_period_since" => "2026-03-01T00:00:00+09:00",
        "synth_period_until" => "2026-07-31T23:59:59+09:00")
      get "/synth/reflections/2026-1"
      expect(last_response).to be_ok
      expect(last_response.body).to include("학기 회고") # type 배지
      expect(last_response.body).to include("2026-03-01") # period since
      expect(last_response.body).to include("/synth/reflections/2026-1/accept")
      expect(last_response.body).to include("/synth/reflections/2026-1/reject")
      # reflections 는 재생성 버튼 없음 (semester_label 폼이 index 에 있음)
      expect(last_response.body).not_to include("/synth/reflections/2026-1/generate")
    end

    it "patterns 상세 — 카테고리 메타 + 재생성 버튼 (고정 slug)" do
      seed_synth("patterns", "lessons",
        "synth_target" => "patterns:lessons",
        "synth_categories" => %w[수업 도덕])
      get "/synth/patterns/lessons"
      expect(last_response).to be_ok
      expect(last_response.body).to include("수업 패턴 후보")
      expect(last_response.body).to include("수업 · 도덕") # 카테고리
      expect(last_response.body).to include("/synth/patterns/lessons/generate") # 재생성
    end

    it "contradictions 상세 — 학생 목록 메타 + 재생성 버튼" do
      seed_synth("contradictions", "observations",
        "synth_target" => "contradictions:observations",
        "synth_students" => %w[민준 서연])
      get "/synth/contradictions/observations"
      expect(last_response).to be_ok
      expect(last_response.body).to include("학생 묘사 변화")
      expect(last_response.body).to include("민준 · 서연") # 학생 목록
      expect(last_response.body).to include("/synth/contradictions/observations/generate")
    end

    it "알 수 없는 type → 404" do
      get "/synth/invalidtype/whatever"
      expect(last_response.status).to eq(404)
    end

    it "알려진 type 이지만 slug 없음 → 404" do
      get "/synth/reflections/#{esc("존재하지않음")}"
      expect(last_response.status).to eq(404)
    end
  end

  describe "POST /synth/:type/:slug/accept — type별 category 매핑" do
    it "reflections 수락 → category=학기회고" do
      seed_synth("reflections", "2026-1", "synth_target" => "semester:2026-1")
      post "/synth/reflections/2026-1/accept"
      expect(last_response).to be_redirect

      year = Time.now.year
      record_dir = vault_dir.join("30_Records", year.to_s, "학기회고")
      expect(record_dir).to exist
      content = File.read(Dir.glob(record_dir.join("*.md")).first)
      expect(content).to include("category: 학기회고")
    end

    it "patterns 수락 → category=수업기록" do
      seed_synth("patterns", "lessons", "synth_target" => "patterns:lessons")
      post "/synth/patterns/lessons/accept"
      expect(last_response).to be_redirect

      year = Time.now.year
      record_dir = vault_dir.join("30_Records", year.to_s, "수업기록")
      expect(record_dir).to exist
    end

    it "contradictions 수락 → category=학생기록 + audit :create + :synth_accept" do
      seed_synth("contradictions", "observations", "synth_target" => "contradictions:observations")
      expect {
        post "/synth/contradictions/observations/accept"
      }.to change { db[:entries].where(mode: "record").count }.by(1)

      audit_actions = audit_log.read_all.map { |r| r["action"] }
      expect(audit_actions).to include("create", "synth_accept")
    end

    it "수락 후 synth 원본 unlink" do
      seed_synth("reflections", "2026-1", "synth_target" => "semester:2026-1")
      post "/synth/reflections/2026-1/accept"
      expect(synth_root.join("reflections/2026-1.md")).not_to exist
    end
  end

  describe "POST /synth/:type/:slug/reject — 4 type 통합 거절" do
    it "reflections 거절 → 휴지통 + audit synth_reject (entry_id prefix=synth:semester:)" do
      seed_synth("reflections", "2026-1", "synth_target" => "semester:2026-1")
      post "/synth/reflections/2026-1/reject"

      expect(last_response).to be_redirect
      expect(synth_root.join("reflections/2026-1.md")).not_to exist
      trashed = vault_dir.join(".sowing/trash/.sowing/synth/reflections/2026-1.md")
      expect(trashed).to exist

      reject_record = audit_log.read_all.find { |r| r["action"] == "synth_reject" }
      expect(reject_record).not_to be_nil
      expect(reject_record["entry_id"]).to eq("synth:semester:2026-1")
    end

    it "patterns 거절 → audit entry_id=synth:patterns:lessons" do
      seed_synth("patterns", "lessons", "synth_target" => "patterns:lessons")
      post "/synth/patterns/lessons/reject"
      reject = audit_log.read_all.find { |r| r["action"] == "synth_reject" }
      expect(reject["entry_id"]).to eq("synth:patterns:lessons")
    end
  end

  describe "POST /synth/reflections/generate — 폼 입력 처리" do
    let(:vault_setup) {
      # 5건 entry 시드 (학기 분량 — MIN_ENTRIES=5 충족)
      FileUtils.mkdir_p(vault_dir.join("00_Inbox"))
      5.times do |i|
        path = "00_Inbox/01REFGEN0000000000000000#{i + 1}.md"
        File.write(vault_dir.join(path),
          "---\nid: 01REFGEN0000000000000000#{i + 1}\nmode: memo\ncreated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\nupdated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\n---\n\n본문 #{i}.")
        db[:entries].insert(
          id: "01REFGEN0000000000000000#{i + 1}", mode: "memo", path: path,
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          updated_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
          word_count: 1, indexed_at: Time.now.iso8601
        )
      end
    }

    it "semester_label + since/until 입력 → 합성 실행 + audit + redirect" do
      vault_setup
      post "/synth/reflections/generate",
        "semester_label" => "2026-1",
        "since" => "2026-05-01T00:00:00+09:00",
        "until_time" => "2026-05-31T23:59:59+09:00"

      expect(last_response).to be_redirect
      expect(synth_root.join("reflections/2026-1.md")).to exist

      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to eq("synth:semester:2026-1")
    end

    it "semester_label 빈 입력 → 실패 flash + 목록으로" do
      post "/synth/reflections/generate", "semester_label" => ""
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
      # 합성 시도 안 함
      expect(audit_log.read_all.any? { |r| r["action"] == "synth_generate" }).to be false
    end

    it "since/until 비우고 default window 사용 — entries 부족하면 fail flash" do
      post "/synth/reflections/generate", "semester_label" => "no-data"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "POST /synth/patterns/lessons/generate — 매개변수 없음" do
    it "수업 카테고리 entries 충분 시 → 생성 + audit + redirect to detail" do
      FileUtils.mkdir_p(vault_dir.join("20_Notes/수업"))
      3.times do |i|
        path = "20_Notes/수업/01LESGEN0000000000000000#{i + 1}.md"
        File.write(vault_dir.join(path),
          "---\nid: 01LESGEN0000000000000000#{i + 1}\nmode: note\ncategory: 수업\ncreated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\nupdated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\n---\n\n협동학습 활기.")
        db[:entries].insert(
          id: "01LESGEN0000000000000000#{i + 1}", mode: "note", path: path,
          category: "수업",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          updated_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
          word_count: 2, indexed_at: Time.now.iso8601
        )
      end

      post "/synth/patterns/lessons/generate"
      expect(last_response).to be_redirect
      expect(synth_root.join("patterns/lessons.md")).to exist

      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to eq("synth:patterns:lessons")
    end

    it "수업 entries 부족 시 → 실패 flash + 목록으로" do
      post "/synth/patterns/lessons/generate"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "POST /synth/contradictions/observations/generate" do
    it "변화 없으면 실패 flash" do
      post "/synth/contradictions/observations/generate"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "POST /synth/consultations/:slug/generate (확장 합성기 #1)" do
    it "학생 entity + 상담 entries 충분 시 → 생성 + audit + redirect to detail" do
      # 학생 entity + 상담 record 2건 시드
      eid = db[:entities].insert(
        type: "student", name: "민준",
        first_seen_at: Time.now.iso8601, last_seen_at: Time.now.iso8601,
        mention_count: 1
      )
      FileUtils.mkdir_p(vault_dir.join("30_Records/2026/상담"))
      2.times do |i|
        path = "30_Records/2026/상담/01PCCSYS000000000000P00#{i + 1}.md"
        File.write(vault_dir.join(path),
          "---\nid: 01PCCSYS000000000000P00#{i + 1}\nmode: record\ncategory: 상담\ncreated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\nupdated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\n---\n\n민준 학부모 면담.")
        db[:entries].insert(
          id: "01PCCSYS000000000000P00#{i + 1}", mode: "record", path: path,
          category: "상담",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          updated_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
          word_count: 2, indexed_at: Time.now.iso8601
        )
        db[:entity_mentions].insert(entity_id: eid, entry_id: "01PCCSYS000000000000P00#{i + 1}")
      end

      post "/synth/consultations/#{esc("민준")}/generate"
      expect(last_response).to be_redirect
      expect(synth_root.join("consultations/민준.md")).to exist

      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to eq("synth:consultation:민준")
    end

    it "학생 entity 없음 → 실패 flash" do
      post "/synth/consultations/#{esc("없는학생")}/generate"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "consultations type 통합 — accept/reject" do
    it "수락 → category=상담 (학생기록과 별도)" do
      seed_synth("consultations", "민준", "synth_target" => "consultation:민준")
      post "/synth/consultations/#{esc("민준")}/accept"
      expect(last_response).to be_redirect

      year = Time.now.year
      record_dir = vault_dir.join("30_Records", year.to_s, "상담")
      expect(record_dir).to exist
    end

    it "거절 → audit entry_id=synth:consultation:민준" do
      seed_synth("consultations", "민준", "synth_target" => "consultation:민준")
      post "/synth/consultations/#{esc("민준")}/reject"
      reject = audit_log.read_all.find { |r| r["action"] == "synth_reject" }
      expect(reject["entry_id"]).to eq("synth:consultation:민준")
    end

    it "GET /synth — 5 섹션 모두 표시 (consultations 추가)" do
      get "/synth"
      expect(last_response).to be_ok
      expect(last_response.body).to include("학부모 상담 준비")
      expect(last_response.body).to include("/synth/consultations/")
    end
  end

  describe "확장 #2 — assessments type" do
    it "GET /synth — 평가 추이 섹션 표시 + generate 폼" do
      get "/synth"
      expect(last_response).to be_ok
      expect(last_response.body).to include("평가 추이")
      expect(last_response.body).to include("/synth/assessments/__SLUG__/generate")
    end

    it "수락 → category=평가기록" do
      seed_synth("assessments", "민준", "synth_target" => "assessment:민준")
      post "/synth/assessments/#{esc("민준")}/accept"
      expect(last_response).to be_redirect
      year = Time.now.year
      expect(vault_dir.join("30_Records", year.to_s, "평가기록")).to exist
    end

    it "거절 → audit entry_id=synth:assessment:민준" do
      seed_synth("assessments", "민준", "synth_target" => "assessment:민준")
      post "/synth/assessments/#{esc("민준")}/reject"
      reject = audit_log.read_all.find { |r| r["action"] == "synth_reject" }
      expect(reject["entry_id"]).to eq("synth:assessment:민준")
    end

    it "POST /synth/assessments/:slug/generate — 학생 entity + 평가 entries 충분" do
      eid = db[:entities].insert(
        type: "student", name: "민준",
        first_seen_at: Time.now.iso8601, last_seen_at: Time.now.iso8601,
        mention_count: 1
      )
      FileUtils.mkdir_p(vault_dir.join("30_Records/2026/평가"))
      2.times do |i|
        path = "30_Records/2026/평가/01ATSYS00000000000000B0#{i + 1}.md"
        File.write(vault_dir.join(path),
          "---\nid: 01ATSYS00000000000000B0#{i + 1}\nmode: record\ncategory: 평가\ncreated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\nupdated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\n---\n\n민준 단원평가 잘 풀었다.")
        db[:entries].insert(
          id: "01ATSYS00000000000000B0#{i + 1}", mode: "record", path: path,
          category: "평가",
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          updated_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
          word_count: 4, indexed_at: Time.now.iso8601
        )
        db[:entity_mentions].insert(entity_id: eid, entry_id: "01ATSYS00000000000000B0#{i + 1}")
      end

      post "/synth/assessments/#{esc("민준")}/generate"
      expect(last_response).to be_redirect
      expect(synth_root.join("assessments/민준.md")).to exist
      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to eq("synth:assessment:민준")
    end
  end

  describe "확장 #3 — trainings type" do
    it "GET /synth — 연수 적용 추적 섹션 표시 + generate 폼" do
      get "/synth"
      expect(last_response).to be_ok
      expect(last_response.body).to include("연수 적용 추적")
      expect(last_response.body).to include("/synth/trainings/__SLUG__/generate")
    end

    it "수락 → category=연수기록" do
      seed_synth("trainings", "01TRACCEPT00000000000000",
        "synth_target" => "training:01TRACCEPT00000000000000")
      post "/synth/trainings/01TRACCEPT00000000000000/accept"
      expect(last_response).to be_redirect
      year = Time.now.year
      expect(vault_dir.join("30_Records", year.to_s, "연수기록")).to exist
    end

    it "POST /synth/trainings/:slug/generate — 연수 노트 entry 존재 시" do
      tid = "01TRSYSGEN0000000000000A"
      FileUtils.mkdir_p(vault_dir.join("20_Notes/trainings"))
      File.write(vault_dir.join("20_Notes/trainings/#{tid}.md"),
        "---\nid: #{tid}\nmode: note\ncategory: trainings\ntitle: 협동학습 연수\ncreated_at: '2026-04-01T09:00:00+09:00'\nupdated_at: '2026-04-01T09:00:00+09:00'\n---\n\n협동학습 모둠 사회자 차시 카드.")
      db[:entries].insert(
        id: tid, mode: "note", path: "20_Notes/trainings/#{tid}.md",
        category: "trainings", title: "협동학습 연수",
        created_at: "2026-04-01T09:00:00+09:00", updated_at: "2026-04-01T09:00:00+09:00",
        file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
        word_count: 5, indexed_at: Time.now.iso8601
      )

      post "/synth/trainings/#{tid}/generate"
      expect(last_response).to be_redirect
      expect(synth_root.join("trainings/#{tid}.md")).to exist

      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to eq("synth:training:#{tid}")
    end

    it "POST generate — followup_days 폼 입력" do
      tid = "01TRSYSDAYS000000000000A"
      FileUtils.mkdir_p(vault_dir.join("20_Notes/trainings"))
      File.write(vault_dir.join("20_Notes/trainings/#{tid}.md"),
        "---\nid: #{tid}\nmode: note\ncategory: trainings\ncreated_at: '2026-04-01T09:00:00+09:00'\nupdated_at: '2026-04-01T09:00:00+09:00'\n---\n\n협동학습 모둠.")
      db[:entries].insert(
        id: tid, mode: "note", path: "20_Notes/trainings/#{tid}.md",
        category: "trainings",
        created_at: "2026-04-01T09:00:00+09:00", updated_at: "2026-04-01T09:00:00+09:00",
        file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
        word_count: 2, indexed_at: Time.now.iso8601
      )

      post "/synth/trainings/#{tid}/generate", "followup_days" => "30"
      expect(last_response).to be_redirect
      fm = FrontMatterParser::Parser.new(:md).call(
        synth_root.join("trainings/#{tid}.md").read
      ).front_matter
      expect(fm["synth_followup_days"]).to eq(30)
    end

    it "training_id 없음 → 실패 flash" do
      post "/synth/trainings/01NOTEXIST00000000000000/generate"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "확장 #4 — weekly type" do
    it "GET /synth — 주간 회고 섹션 + generate 폼 (week_label/since/until)" do
      get "/synth"
      expect(last_response).to be_ok
      expect(last_response.body).to include("주간 회고")
      expect(last_response.body).to include('action="/synth/weekly/generate"')
      expect(last_response.body).to include('name="week_label"')
    end

    it "수락 → category=주간회고" do
      seed_synth("weekly", "2026-W19", "synth_target" => "week:2026-W19")
      post "/synth/weekly/2026-W19/accept"
      expect(last_response).to be_redirect
      year = Time.now.year
      expect(vault_dir.join("30_Records", year.to_s, "주간회고")).to exist
    end

    it "POST /synth/weekly/generate — 입력 entries 충분 시 생성 + audit" do
      FileUtils.mkdir_p(vault_dir.join("00_Inbox"))
      path = "00_Inbox/01WKSYS00000000000000B01.md"
      File.write(vault_dir.join(path),
        "---\nid: 01WKSYS00000000000000B01\nmode: memo\ncreated_at: '#{Time.now.iso8601}'\nupdated_at: '#{Time.now.iso8601}'\n---\n\n주간 메모.")
      db[:entries].insert(
        id: "01WKSYS00000000000000B01", mode: "memo", path: path,
        created_at: Time.now.iso8601, updated_at: Time.now.iso8601,
        file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
        word_count: 1, indexed_at: Time.now.iso8601
      )

      post "/synth/weekly/generate"
      expect(last_response).to be_redirect
      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to start_with("synth:week:")
    end

    it "POST /synth/weekly/generate — entries 0건 → 실패 flash" do
      post "/synth/weekly/generate", "since" => "2026-04-01T00:00:00+09:00", "until_time" => "2026-04-07T23:59:59+09:00"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "확장 #5 — orphans type" do
    it "GET /synth — 고립 entries 섹션 + generate 폼" do
      get "/synth"
      expect(last_response).to be_ok
      expect(last_response.body).to include("고립 entries")
      expect(last_response.body).to include("/synth/orphans/observations/generate")
    end

    it "수락 → category=메모회고" do
      seed_synth("orphans", "observations", "synth_target" => "orphans:observations")
      post "/synth/orphans/observations/accept"
      expect(last_response).to be_redirect
      year = Time.now.year
      expect(vault_dir.join("30_Records", year.to_s, "메모회고")).to exist
    end

    it "POST /synth/orphans/observations/generate — entries 0건 → 실패 flash" do
      post "/synth/orphans/observations/generate"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end

    it "POST generate — backlink 0 entry 1+ 시 → 생성 + audit" do
      FileUtils.mkdir_p(vault_dir.join("00_Inbox"))
      path = "00_Inbox/01ORSYS00000000000000C01.md"
      File.write(vault_dir.join(path),
        "---\nid: 01ORSYS00000000000000C01\nmode: memo\ncreated_at: '#{Time.now.iso8601}'\nupdated_at: '#{Time.now.iso8601}'\n---\n\n고립 메모.")
      db[:entries].insert(
        id: "01ORSYS00000000000000C01", mode: "memo", path: path,
        created_at: Time.now.iso8601, updated_at: Time.now.iso8601,
        file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
        word_count: 1, indexed_at: Time.now.iso8601
      )

      post "/synth/orphans/observations/generate"
      expect(last_response).to be_redirect
      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to eq("synth:orphans:observations")
    end
  end

  describe "확장 #6 — lesson-series type" do
    it "GET /synth — 수업 시리즈 섹션 + generate 폼" do
      get "/synth"
      expect(last_response.body).to include("수업 시리즈")
      expect(last_response.body).to include("/synth/lesson-series/__SLUG__/generate")
    end

    it "수락 → category=수업기록" do
      seed_synth("lesson-series", "분수", "synth_target" => "series:분수")
      post "/synth/lesson-series/#{esc("분수")}/accept"
      expect(last_response).to be_redirect
      year = Time.now.year
      expect(vault_dir.join("30_Records", year.to_s, "수업기록")).to exist
    end

    it "POST generate — 키워드 매칭 entries 2건+ 시 생성" do
      FileUtils.mkdir_p(vault_dir.join("00_Inbox"))
      2.times do |i|
        path = "00_Inbox/01LSSYS0000000000000B0#{i + 1}.md"
        File.write(vault_dir.join(path),
          "---\nid: 01LSSYS0000000000000B0#{i + 1}\nmode: memo\ncreated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\nupdated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\n---\n\n분수 수업 #{i}.")
        db[:entries].insert(
          id: "01LSSYS0000000000000B0#{i + 1}", mode: "memo", path: path,
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          updated_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
          word_count: 2, indexed_at: Time.now.iso8601
        )
      end
      post "/synth/lesson-series/#{esc("분수")}/generate"
      expect(last_response).to be_redirect
      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to eq("synth:series:분수")
    end

    it "POST generate — 키워드 매칭 0 → 실패 flash" do
      post "/synth/lesson-series/#{esc("없는단원")}/generate"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "확장 #7 — tag-clusters type" do
    it "GET /synth — 태그 클러스터 섹션 + generate 폼" do
      get "/synth"
      expect(last_response.body).to include("태그 클러스터")
      expect(last_response.body).to include("/synth/tag-clusters/topics/generate")
    end

    it "수락 → category=주제정리" do
      seed_synth("tag-clusters", "topics", "synth_target" => "clusters:topics")
      post "/synth/tag-clusters/topics/accept"
      expect(last_response).to be_redirect
      year = Time.now.year
      expect(vault_dir.join("30_Records", year.to_s, "주제정리")).to exist
    end

    it "POST generate — 빈 DB → 실패 flash" do
      post "/synth/tag-clusters/topics/generate"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "확장 #8 — seasonal type" do
    it "GET /synth — 계절성 패턴 섹션 + generate 폼 (current 자동)" do
      get "/synth"
      expect(last_response.body).to include("계절성 패턴")
      expect(last_response.body).to include('action="/synth/seasonal/current/generate"')
    end

    it "수락 → category=계절회고" do
      seed_synth("seasonal", "05", "synth_target" => "season:05")
      post "/synth/seasonal/05/accept"
      expect(last_response).to be_redirect
      year = Time.now.year
      expect(vault_dir.join("30_Records", year.to_s, "계절회고")).to exist
    end

    it "POST /synth/seasonal/05/generate — 5월 entries 충분 시 생성" do
      FileUtils.mkdir_p(vault_dir.join("00_Inbox"))
      3.times do |i|
        path = "00_Inbox/01SESYS0000000000000C0#{i + 1}.md"
        File.write(vault_dir.join(path),
          "---\nid: 01SESYS0000000000000C0#{i + 1}\nmode: memo\ncreated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\nupdated_at: '2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00'\n---\n\n5월 entry #{i}.")
        db[:entries].insert(
          id: "01SESYS0000000000000C0#{i + 1}", mode: "memo", path: path,
          created_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          updated_at: "2026-05-#{(i + 1).to_s.rjust(2, "0")}T09:00:00+09:00",
          file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
          word_count: 2, indexed_at: Time.now.iso8601
        )
      end
      post "/synth/seasonal/05/generate"
      expect(last_response).to be_redirect
      expect(synth_root.join("seasonal/05.md")).to exist
      gen = audit_log.read_all.find { |r| r["action"] == "synth_generate" }
      expect(gen["entry_id"]).to eq("synth:season:05")
    end

    it "POST /synth/seasonal/current/generate — 슬러그 'current' = 이번 달 자동" do
      FileUtils.mkdir_p(vault_dir.join("00_Inbox"))
      now_month = Time.now.month
      now_year = Time.now.year
      3.times do |i|
        day = (i + 1).to_s.rjust(2, "0")
        ts = "#{now_year}-#{now_month.to_s.rjust(2, "0")}-#{day}T09:00:00+09:00"
        path = "00_Inbox/01SECUR0000000000000C0#{i + 1}.md"
        File.write(vault_dir.join(path),
          "---\nid: 01SECUR0000000000000C0#{i + 1}\nmode: memo\ncreated_at: '#{ts}'\nupdated_at: '#{ts}'\n---\n\n이번 달 entry.")
        db[:entries].insert(
          id: "01SECUR0000000000000C0#{i + 1}", mode: "memo", path: path,
          created_at: ts, updated_at: ts,
          file_mtime: Time.now.to_i, file_hash: "deadbeef00000000",
          word_count: 2, indexed_at: Time.now.iso8601
        )
      end
      post "/synth/seasonal/current/generate"
      expect(last_response).to be_redirect
      mm = now_month.to_s.rjust(2, "0")
      expect(synth_root.join("seasonal/#{mm}.md")).to exist
    end
  end

  describe "GET /synth/metrics — 베타 검증 인프라" do
    it "이벤트 0건 → 빈 상태 안내" do
      get "/synth/metrics"
      expect(last_response).to be_ok
      expect(last_response.body).to include("아직 합성 이벤트가 없습니다")
    end

    it "synth_* 이벤트 있을 때 — 전체 + type 별 + 주별 표시" do
      audit_log.append(action: :synth_generate,
        entry_id: "synth:students:민준",
        mode: "record",
        path: ".sowing/synth/students/민준.md")
      audit_log.append(action: :synth_accept,
        entry_id: "01ACPT00000000000000000001",
        mode: "record",
        path: ".sowing/synth/students/민준.md")
      audit_log.append(action: :synth_reject,
        entry_id: "synth:reflections:2026-1",
        mode: "record",
        path: ".sowing/synth/reflections/2026-1.md")

      get "/synth/metrics"
      expect(last_response).to be_ok
      # 전체 지표
      expect(last_response.body).to include("전체 지표")
      expect(last_response.body).to include("Phase 11 마일스톤")
      # 수락률 100% (1 accept / 1 decided) — 50% 이상
      expect(last_response.body).to include("100.0%")
      expect(last_response.body).to include("✅ Phase 11 마일스톤")
      # type 별
      expect(last_response.body).to include("학생 디제스트")
      expect(last_response.body).to include("학기 회고")
      # rake CLI 안내
      expect(last_response.body).to include("rake stats:beta_report")
    end

    it "수락률 < 50% — 미달성 마커" do
      audit_log.append(action: :synth_generate,
        entry_id: "synth:students:a", mode: "record",
        path: ".sowing/synth/students/a.md")
      audit_log.append(action: :synth_reject,
        entry_id: "synth:students:a", mode: "record",
        path: ".sowing/synth/students/a.md")

      get "/synth/metrics"
      expect(last_response.body).to include("0.0%")
      expect(last_response.body).to include("🟡 Phase 11 마일스톤")
    end
  end

  describe "ADR-013 — 자율 mutation 0 (4 type 통합 검증)" do
    it "GET /synth + GET /synth/:type/:slug 만으로는 vault·audit 변화 0" do
      seed_synth("students", "민준", "synth_target" => "student:민준")
      seed_synth("reflections", "2026-1", "synth_target" => "semester:2026-1")
      audit_before = audit_log.read_all.size
      entries_before = db[:entries].count

      get "/synth"
      get "/synth/students/#{esc("민준")}"
      get "/synth/reflections/2026-1"

      expect(audit_log.read_all.size).to eq(audit_before)
      expect(db[:entries].count).to eq(entries_before)
      expect(synth_root.join("students/민준.md")).to exist
      expect(synth_root.join("reflections/2026-1.md")).to exist
    end
  end
end
