# frozen_string_literal: true

# 30년 시나리오 #4 — `/graph` + `/api/graph_data` 라우트.

require "rack/test"
require "fileutils"
require "json"

RSpec.describe "위키링크 그래프 (#4)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }
  let(:vault_dir) { Sowing::Core::Paths.vault_dir }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entries_fts].delete
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    FileUtils.rm_rf(vault_dir.join("30_Records"))
  end

  let(:seed_counter) { @seed_counter ||= [0] }
  def seed_record(title:, created_at:, category: "수업회고")
    seed_counter[0] += 1
    rid = "01GRPH" + format("%020d", seed_counter[0])
    year = created_at[0, 4]
    path = "30_Records/#{year}/#{category}/r-#{seed_counter[0]}.md"
    FileUtils.mkdir_p(vault_dir.join(path).dirname)
    File.write(vault_dir.join(path),
      "---\nid: #{rid}\nmode: record\ncategory: #{category}\ntitle: #{title}\ncreated_at: '#{created_at}'\nupdated_at: '#{created_at}'\n---\n\n본문\n")
    db[:entries].insert(
      id: rid, path: path, mode: "record",
      category: category, title: title,
      created_at: created_at, updated_at: created_at,
      file_mtime: Time.iso8601(created_at).to_i, file_hash: "0" * 16,
      word_count: 1, indexed_at: created_at
    )
    rid
  end

  def link(source_id, target_id, target_text: nil)
    db[:links].insert(
      source_id: source_id, target_id: target_id,
      target_text: target_text || target_id
    )
  end

  describe "GET /graph" do
    it "200 OK + 페이지 헤더 + 필터 폼 + SVG 컨테이너 + Stimulus controller 등록" do
      get "/graph"
      expect(last_response).to be_ok
      expect(last_response.body).to include("위키링크 그래프")
      expect(last_response.body).to include('data-controller="graph"')
      expect(last_response.body).to include("data-graph-target=\"svg\"")
      expect(last_response.body).to include("/api/graph_data")
      expect(last_response.body).to include("범례")
    end

    it "기본 모드 모두 체크 (memo/note/record)" do
      get "/graph"
      %w[memo note record].each do |m|
        expect(last_response.body).to match(/value="#{m}"\s+checked/)
      end
    end

    it "쿼리 파라미터가 API URL 에 그대로 전달" do
      get "/graph?modes[]=record&max=50"
      expect(last_response.body).to include("/api/graph_data?modes")
      expect(last_response.body).to include("max=50")
    end
  end

  describe "GET /api/graph_data" do
    it "JSON content-type + nodes/edges/truncated/total 스키마" do
      a = seed_record(title: "A", created_at: "2024-01-01T09:00:00+09:00")
      b = seed_record(title: "B", created_at: "2024-02-01T09:00:00+09:00")
      link(a, b)

      get "/api/graph_data"
      expect(last_response).to be_ok
      expect(last_response.headers["content-type"]).to include("application/json")
      data = JSON.parse(last_response.body)
      expect(data).to have_key("nodes")
      expect(data).to have_key("edges")
      expect(data).to have_key("truncated")
      expect(data).to have_key("total")
      expect(data["nodes"].size).to eq(2)
      expect(data["edges"].size).to eq(1)
    end

    it "각 노드에 href 필드 포함 (entry 상세 라우트)" do
      seed_record(title: "A", created_at: "2024-01-01T09:00:00+09:00")
      get "/api/graph_data"
      data = JSON.parse(last_response.body)
      node = data["nodes"].first
      expect(node["href"]).to start_with("/records/")
    end

    it "0 entries — 빈 배열" do
      get "/api/graph_data"
      data = JSON.parse(last_response.body)
      expect(data["nodes"]).to eq([])
      expect(data["edges"]).to eq([])
      expect(data["truncated"]).to be false
    end

    it "truncated 플래그 — max 초과 시 (max 는 controller 가 [10, 1000] clamp)" do
      12.times do |i|
        mm = format("%02d", (i % 12) + 1)
        seed_record(title: "n#{i}", created_at: "2024-#{mm}-#{format("%02d", (i % 28) + 1)}T09:00:00+09:00")
      end
      get "/api/graph_data?max=10"
      data = JSON.parse(last_response.body)
      expect(data["nodes"].size).to eq(10)
      expect(data["truncated"]).to be true
      expect(data["total"]).to eq(12)
    end

    it "필터 — modes/categories/since/until 모두 적용" do
      seed_record(title: "수업1", category: "수업회고", created_at: "2024-01-01T09:00:00+09:00")
      seed_record(title: "상담1", category: "상담", created_at: "2024-02-01T09:00:00+09:00")
      seed_record(title: "수업2", category: "수업회고", created_at: "2025-03-01T09:00:00+09:00")

      get "/api/graph_data?categories[]=#{Rack::Utils.escape("수업회고")}&since=2024-01-01&until=2024-12-31"
      data = JSON.parse(last_response.body)
      expect(data["nodes"].size).to eq(1)
      expect(data["nodes"].first["title"]).to eq("수업1")
    end
  end

  describe "ADR-013 — 그래프 시각화는 read-only" do
    it "GET 만으로 vault·DB 변경 0" do
      seed_record(title: "x", created_at: "2024-01-01T09:00:00+09:00")
      before_count = db[:entries].count
      audit_count = Sowing::Core::AuditLog.instance.read_all.size

      get "/graph"
      get "/api/graph_data"

      expect(db[:entries].count).to eq(before_count)
      expect(Sowing::Core::AuditLog.instance.read_all.size).to eq(audit_count)
    end
  end
end
