# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "기록으로 승격 (W3-T07)", type: :request do
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
    FileUtils.rm_rf(vault_dir.join(".sowing"))
  end

  def create_memo
    post "/memos", body: "오늘 1교시 활기"
    db[:entries].where(mode: "memo").first[:id]
  end

  def create_note
    post "/notes",
      "title" => "협동학습 정리",
      "body" => "본문",
      "category" => "trainings",
      "source" => "연수"
    db[:entries].where(mode: "note").first[:id]
  end

  describe "메모 → 기록 (MemosController)" do
    describe "GET /memos/:id/promote_to_record" do
      let!(:id) { create_memo }

      it "200 OK + 폼 + 자유 카테고리 datalist" do
        get "/memos/#{id}/promote_to_record"
        expect(last_response).to be_ok
        expect(last_response.body).to include("기록으로 승격")
        expect(last_response.body).to include('id="record_title"')
        expect(last_response.body).to include('id="record_category"')
        expect(last_response.body).to include('list="record_categories_datalist"')
      end

      it "원본 메모 본문 미리보기 details" do
        get "/memos/#{id}/promote_to_record"
        expect(last_response.body).to include("원본 메모 본문 보기")
        expect(last_response.body).to include("오늘 1교시 활기")
      end

      it "없는 id → 404" do
        get "/memos/01XXXXXXXXXXXXXXXXXXXXXXXX/promote_to_record"
        expect(last_response.status).to eq(404)
      end
    end

    describe "POST /memos/:id/promote_to_record (정상)" do
      let!(:id) { create_memo }

      before do
        post "/memos/#{id}/promote_to_record",
          "title" => "오늘의 회고",
          "category" => "수업철학"
      end

      it "/records/:id로 redirect" do
        expect(last_response.status).to be_between(300, 399)
        expect(last_response.headers["location"]).to end_with("/records/#{id}")
      end

      it "옛 메모 → 휴지통, 새 30_Records/{YYYY}/{category}/{title}.md 생성" do
        year = Time.now.year
        expect(Dir.glob(vault_dir.join("00_Inbox/*.md"))).to be_empty
        expect(vault_dir.join("30_Records/#{year}/수업철학/오늘의 회고.md")).to exist
      end

      it "인덱스 mode = :record + promoted_from 채워짐" do
        indexed = Sowing::Repositories::IndexRepo.new.find(id)
        expect(indexed.mode).to eq(:record)
        expect(indexed.promoted_from).to start_with("00_Inbox/")
      end
    end

    describe "POST /memos/:id/promote_to_record (검증 실패)" do
      let!(:id) { create_memo }

      it "title 비면 422 + 폼 에코 (datalist 다시 렌더)" do
        post "/memos/#{id}/promote_to_record", "title" => "", "category" => "수업"
        expect(last_response.status).to eq(422)
        expect(last_response.body).to include("제목을 입력")
        expect(last_response.body).to include('list="record_categories_datalist"')
      end

      it "category 비면 422" do
        post "/memos/#{id}/promote_to_record", "title" => "T", "category" => ""
        expect(last_response.status).to eq(422)
        expect(last_response.body).to include("카테고리를 입력")
      end

      it "실패 시 메모는 그대로 (mode 변화 없음)" do
        post "/memos/#{id}/promote_to_record", "title" => "", "category" => "X"
        expect(Sowing::Repositories::IndexRepo.new.find(id).mode).to eq(:memo)
      end
    end
  end

  describe "필기 → 기록 (NotesController)" do
    describe "GET /notes/:id/promote_to_record" do
      let!(:id) { create_note }

      it "200 OK + 폼 + 필기 정보 미리보기" do
        get "/notes/#{id}/promote_to_record"
        expect(last_response).to be_ok
        expect(last_response.body).to include("기록으로 승격")
        expect(last_response.body).to include("협동학습 정리") # 원본 title prefill
        expect(last_response.body).to include("연수")          # 원본 source 표시
      end

      it "원본 필기 정보 details에 분류·출처·작성일 표시" do
        get "/notes/#{id}/promote_to_record"
        expect(last_response.body).to include("원본 필기 정보 보기")
      end

      it "없는 id → 404" do
        get "/notes/01XXXXXXXXXXXXXXXXXXXXXXXX/promote_to_record"
        expect(last_response.status).to eq(404)
      end
    end

    describe "POST /notes/:id/promote_to_record (정상)" do
      let!(:id) { create_note }

      before do
        post "/notes/#{id}/promote_to_record",
          "title" => "협동학습 영구 보관본",
          "category" => "수업철학"
      end

      it "/records/:id로 redirect" do
        expect(last_response.status).to be_between(300, 399)
        expect(last_response.headers["location"]).to end_with("/records/#{id}")
      end

      it "옛 필기 (20_Notes/trainings/...) → 휴지통, 새 30_Records 생성" do
        year = Time.now.year
        expect(vault_dir.join("20_Notes/trainings/협동학습 정리.md")).not_to exist
        expect(vault_dir.join("30_Records/#{year}/수업철학/협동학습 영구 보관본.md")).to exist
        expect(vault_dir.join(".sowing/trash/20_Notes/trainings/협동학습 정리.md")).to exist
      end

      it "인덱스 mode = :record + promoted_from 채워짐" do
        indexed = Sowing::Repositories::IndexRepo.new.find(id)
        expect(indexed.mode).to eq(:record)
        expect(indexed.promoted_from).to start_with("20_Notes/")
      end
    end

    describe "POST /notes/:id/promote_to_record (검증 실패)" do
      let!(:id) { create_note }

      it "title 비면 422" do
        post "/notes/#{id}/promote_to_record", "title" => "", "category" => "X"
        expect(last_response.status).to eq(422)
      end

      it "Record id로 시도 → 404 (이미 record는 not_promotable)" do
        post "/records",
          "title" => "이미 record",
          "body" => "본문",
          "category" => "X"
        record_id = db[:entries].where(mode: "record").first[:id]
        # /notes/:id/... 경로니까 find_note에서 이미 mode mismatch로 404
        post "/notes/#{record_id}/promote_to_record",
          "title" => "T", "category" => "X"
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe "UI 진입점" do
    it "메모 카드에 기록으로 승격 링크" do
      id = create_memo
      get "/memos"
      expect(last_response.body).to include("/memos/#{id}/promote_to_record")
      expect(last_response.body).to include("기록으로 승격")
    end

    it "필기 show에 기록으로 승격 버튼" do
      id = create_note
      get "/notes/#{id}"
      expect(last_response.body).to include("/notes/#{id}/promote_to_record")
      expect(last_response.body).to include("기록으로 승격")
    end
  end
end
