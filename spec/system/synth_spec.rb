# frozen_string_literal: true

require "rack/test"
require "fileutils"
require "json"

RSpec.describe "합성 결과 검토 UI (W17-T04)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }
  let(:synth_dir) { vault_dir.join(".sowing/synth/students") }
  let(:audit_log) { Sowing::Core::AuditLog.instance }

  def app
    Sowing::Application
  end

  # Rack::Test 는 non-ASCII URI 거부 → 명시적 escape.
  def esc(s)
    Rack::Utils.escape(s)
  end

  # 합성 디제스트 파일 직접 시드 — 실제 SynthesizeStudentDigest 와 동일한 frontmatter 형식.
  def seed_synth(slug, title: "학생 관찰: #{slug}", model: "deterministic", body: "## 인용\n\n> 발표를 잘 했다.")
    FileUtils.mkdir_p(synth_dir)
    fm = {
      "is_synth" => true,
      "synth_target" => "student:#{slug}",
      "synth_at" => Time.now.iso8601,
      "synth_source_count" => 1,
      "synth_model" => model,
      "title" => title
    }
    yaml = YAML.dump(fm).delete_prefix("---\n")
    File.write(synth_dir.join("#{slug}.md"), "---\n#{yaml}---\n\n# #{title}\n\n#{body}\n")
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

  describe "GET /synth — 목록" do
    it "synth 디렉토리 비어있으면 빈 상태 안내" do
      get "/synth"
      expect(last_response).to be_ok
      expect(last_response.body).to include("검토 대기 중인 합성 결과가 없습니다")
    end

    it "합성 디제스트가 있으면 카드로 나열 + 'LLM 합성' 배지 표시" do
      seed_synth("민준")
      seed_synth("서연", model: "openai:gpt-4o-mini")
      get "/synth"
      expect(last_response).to be_ok
      expect(last_response.body).to include("학생 관찰: 민준")
      expect(last_response.body).to include("학생 관찰: 서연")
      expect(last_response.body).to include("LLM 합성") # 배지
      expect(last_response.body).to include("openai:gpt-4o-mini") # 모델 라벨
      # 명시적 사용자 클릭 (ADR-013 자율 mutation 0)
      expect(last_response.body).to include("/synth/students/민준/accept")
      expect(last_response.body).to include("/synth/students/서연/reject")
    end
  end

  describe "GET /synth/students/:slug — 상세" do
    it "200 + 본문(마크다운→HTML) + 액션 버튼 표시" do
      seed_synth("민준", body: "## 변화 요약\n\n발표를 잘 했다.")
      get "/synth/students/#{esc("민준")}"
      expect(last_response).to be_ok
      expect(last_response.body).to include("학생 관찰: 민준")
      expect(last_response.body).to include("<h2>변화 요약</h2>") # 마크다운 렌더
      expect(last_response.body).to include("/accept")
      expect(last_response.body).to include("/reject")
      expect(last_response.body).to include("/generate") # 재생성
    end

    it "존재하지 않는 slug → 404" do
      get "/synth/students/#{esc("없는학생")}"
      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("합성 결과를 찾을 수 없습니다")
    end
  end

  describe "POST /synth/students/:slug/accept — 수락" do
    before { seed_synth("민준", body: "발표를 잘 했다.") }

    it "정식 record 로 변환 + persist + synth 원본 제거 + audit 2줄(:create + :synth_accept)" do
      expect {
        post "/synth/students/#{esc("민준")}/accept"
      }.to change { db[:entries].where(mode: "record").count }.by(1)

      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")

      # synth 원본 제거됨 (새 record 가 보존된 형태)
      expect(synth_dir.join("민준.md")).not_to exist

      # 새 record 가 30_Records/{YYYY}/인물/ 에 생김
      year = Time.now.year
      record_dir = vault_dir.join("30_Records", year.to_s, "인물")
      expect(record_dir).to exist
      record_files = Dir.glob(record_dir.join("*.md"))
      expect(record_files.size).to eq(1)
      content = File.read(record_files.first)
      expect(content).to include("발표를 잘 했다") # 본문
      expect(content).to include("category: 인물")

      # audit: persist! 의 :create + 컨트롤러의 :synth_accept
      audit_lines = audit_log.read_all
      actions = audit_lines.map { |r| r["action"] }
      expect(actions).to include("create", "synth_accept")
    end
  end

  describe "POST /synth/students/:slug/reject — 거절" do
    before { seed_synth("서연") }

    it "휴지통 이동 + audit :synth_reject + entries 변동 없음" do
      expect {
        post "/synth/students/#{esc("서연")}/reject"
      }.not_to change { db[:entries].count }

      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")

      # 원본 제거 + 휴지통 이동 (trash 내 .sowing/synth/students/ 경로 그대로 보존)
      expect(synth_dir.join("서연.md")).not_to exist
      trashed = vault_dir.join(".sowing/trash/.sowing/synth/students/서연.md")
      expect(trashed).to exist

      # audit
      audit_lines = audit_log.read_all
      reject_record = audit_lines.find { |r| r["action"] == "synth_reject" }
      expect(reject_record).not_to be_nil
      expect(reject_record["entry_id"]).to eq("synth:student:서연")
      expect(reject_record["path"]).to include(".sowing/synth/students/서연.md")
    end

    it "존재하지 않는 slug → 404" do
      post "/synth/students/#{esc("없음")}/reject"
      expect(last_response.status).to eq(404)
    end
  end

  describe "POST /synth/students/:slug/generate — 재생성" do
    before do
      # 학생 entity + mention 시드 — SynthesizeStudentDigest 가 entry 를 인용해야 하므로
      # 실제 entry 도 vault 에 만들어 row.path 에서 읽도록 함.
      FileUtils.mkdir_p(vault_dir.join("00_Inbox"))
      memo_path = "00_Inbox/2026-05-09_120000.md"
      File.write(vault_dir.join(memo_path),
        "---\nid: 01KR1MEMO0000000000000001\nmode: memo\ncreated_at: 2026-05-09T12:00:00+09:00\n---\n\n민준이 발표를 잘 했다.")
      entry_id = "01KR1MEMO0000000000000001"
      db[:entries].insert(
        id: entry_id, mode: "memo", path: memo_path,
        created_at: "2026-05-09T12:00:00+09:00", updated_at: "2026-05-09T12:00:00+09:00",
        file_mtime: Time.now.to_i, file_hash: "0" * 16, word_count: 4,
        indexed_at: Time.now.iso8601
      )
      ent_id = db[:entities].insert(
        type: "student", name: "민준",
        first_seen_at: Time.now.iso8601, last_seen_at: Time.now.iso8601,
        mention_count: 1
      )
      db[:entity_mentions].insert(entity_id: ent_id, entry_id: entry_id, position: 0)
    end

    it "결정적 합성 실행 + synth 파일 생성 + audit :synth_generate" do
      post "/synth/students/#{esc("민준")}/generate"
      expect(last_response).to be_redirect

      expect(synth_dir.join("민준.md")).to exist
      content = synth_dir.join("민준.md").read
      expect(content).to include("is_synth: true")
      expect(content).to include("민준")

      audit_lines = audit_log.read_all
      gen_record = audit_lines.find { |r| r["action"] == "synth_generate" }
      expect(gen_record).not_to be_nil
      expect(gen_record["entry_id"]).to eq("synth:student:민준")
    end

    it "entity 없음 → 실패 flash + 목록으로 redirect" do
      post "/synth/students/#{esc("없는학생")}/generate"
      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/synth")
    end
  end

  describe "ADR-013 — 자율 mutation 0" do
    it "GET /synth 만으로는 vault 또는 audit 에 변화 없음" do
      seed_synth("민준")
      audit_before = audit_log.read_all.size
      entries_before = db[:entries].count

      get "/synth"
      get "/synth/students/#{esc("민준")}"

      expect(audit_log.read_all.size).to eq(audit_before)
      expect(db[:entries].count).to eq(entries_before)
      expect(synth_dir.join("민준.md")).to exist # 원본 유지
    end
  end
end
