# frozen_string_literal: true

require "rack/test"
require "fileutils"
require "json"

RSpec.describe "GET /api/wiki_complete (W3-T03)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    FileUtils.rm_rf(vault_dir.join("00_Inbox"))
    FileUtils.rm_rf(vault_dir.join("20_Notes"))
    FileUtils.rm_rf(vault_dir.join("30_Records"))
  end

  def parsed_response
    JSON.parse(last_response.body, symbolize_names: true)
  end

  def create_note(title, body: "필기 본문")
    post "/notes", "title" => title, "body" => body, "category" => "lessons", "source" => "교과서"
  end

  def create_record(title, category: "학급운영", body: "기록 본문")
    post "/records", "title" => title, "body" => body, "category" => category
  end

  def create_memo(body)
    post "/memos", body: body
  end

  describe "응답 형식 (ADR-004)" do
    before do
      create_note("회고 정리")
      get "/api/wiki_complete", q: "회고"
    end

    it "200 OK + application/json" do
      expect(last_response).to be_ok
      expect(last_response.headers["content-type"]).to include("application/json")
    end

    it "{ results: [...] } 구조" do
      expect(parsed_response).to have_key(:results)
      expect(parsed_response[:results]).to be_an(Array)
    end

    it "각 항목은 path/title/mode/icon 4개 키" do
      item = parsed_response[:results].first
      expect(item.keys).to contain_exactly(:path, :title, :mode, :icon)
    end

    it "mode별 icon이 ADR-004와 일치 (📖/📝/💭)" do
      create_record("기록1")
      create_memo("메모1 본문")
      get "/api/wiki_complete?q="

      icons_by_mode = parsed_response[:results].group_by { |r| r[:mode] }
        .transform_values { |arr| arr.map { |r| r[:icon] }.uniq }
      expect(icons_by_mode["record"]).to eq(["📖"])
      expect(icons_by_mode["note"]).to eq(["📝"])
      expect(icons_by_mode["memo"]).to eq(["💭"])
    end
  end

  describe "정렬 (ROADMAP 해석: 모드 우선 → 최근)" do
    before do
      create_memo("최신 메모")
      sleep 0.01
      create_note("필기 1")
      sleep 0.01
      create_record("기록 1")
    end

    it "q 빈 경우 record → note → memo 순으로 정렬된다" do
      get "/api/wiki_complete?q="
      modes = parsed_response[:results].map { |r| r[:mode] }
      expect(modes).to eq(%w[record note memo])
    end
  end

  describe "q 매칭" do
    before do
      create_note("회고 정리")
      create_note("수업 1단원")
      create_record("회고 5월")
      create_memo("회고 본문 메모")
    end

    it "title substring으로 record/note는 매칭" do
      get "/api/wiki_complete", q: "회고"
      titles = parsed_response[:results].map { |r| r[:title] }
      expect(titles).to include("회고 정리", "회고 5월")
    end

    it "메모는 title이 nil이므로 q 매칭에서 제외 (W3-T03 한계)" do
      get "/api/wiki_complete", q: "회고"
      modes = parsed_response[:results].map { |r| r[:mode] }
      expect(modes).not_to include("memo")
    end

    it "매칭 안 되는 q는 빈 배열" do
      get "/api/wiki_complete", q: "없는키워드"
      expect(parsed_response[:results]).to be_empty
    end
  end

  describe "메모 display title — (메모) 본문 첫 60자" do
    before { create_memo("이것은 충분히 긴 메모 본문입니다. " * 5) }

    it "memo entry의 title 키는 '(메모) {본문 첫 60자}' 형식" do
      get "/api/wiki_complete?q="
      memo_item = parsed_response[:results].find { |r| r[:mode] == "memo" }
      expect(memo_item[:title]).to start_with("(메모) ")
      excerpt_part = memo_item[:title].sub("(메모) ", "")
      expect(excerpt_part.length).to be <= 60
      expect(excerpt_part).to start_with("이것은 충분히 긴")
    end
  end

  describe "limit" do
    it "최대 25건만 반환한다" do
      30.times { |i| create_note("필기 #{i}") }
      get "/api/wiki_complete?q="
      expect(parsed_response[:results].size).to eq(25)
    end
  end

  describe "성능 게이트 (10,000건 < 100ms)" do
    it "10,000건 entries에서 q 매칭이 100ms 미만" do
      # 빠른 시드: SQL 직접 INSERT (도메인 검증 우회 — 인덱스 동작만 측정)
      now_iso = Time.now.iso8601
      rows = (1..10_000).map do |i|
        # ULID-style fake id — IndexRepo는 entries.id에 검증 안 함
        id = "01KR#{i.to_s.rjust(22, "0")[-22..]}"
        {
          id: id,
          path: "20_Notes/lessons/seed-#{i}.md",
          mode: "note",
          title: "필기 시드 #{i}",
          created_at: now_iso,
          updated_at: now_iso,
          file_mtime: 0,
          file_hash: "deadbeef12345678",
          word_count: 0,
          indexed_at: now_iso
        }
      end
      db[:entries].multi_insert(rows)
      expect(db[:entries].count).to be >= 10_000

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      get "/api/wiki_complete", q: "시드 5"
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

      expect(last_response).to be_ok
      expect(parsed_response[:results].size).to be > 0
      expect(elapsed_ms).to be < 100,
        "GET /api/wiki_complete took #{elapsed_ms.round(1)}ms (target < 100ms, 10,000 entries)"
    end
  end

  describe "엣지 케이스" do
    it "빈 DB에서 q 빈 호출 → 빈 results" do
      get "/api/wiki_complete?q="
      expect(parsed_response[:results]).to eq([])
    end

    it "양 끝 공백은 strip되어 처리" do
      create_note("회고")
      get "/api/wiki_complete", q: "  회고  "
      expect(parsed_response[:results].size).to eq(1)
    end
  end
end
