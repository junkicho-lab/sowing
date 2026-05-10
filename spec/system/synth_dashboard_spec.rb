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
