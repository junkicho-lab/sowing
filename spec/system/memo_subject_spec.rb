# frozen_string_literal: true

require "rack/test"
require "fileutils"

# Phase 16 P16-T02 — quick_modal 에 subject 4축 (ADR-016) dropdown 추가.
RSpec.describe "Memo Subject Picker (Phase 16 P16-T02)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    FileUtils.rm_rf(Sowing::Core::Paths.vault_dir.join("00_Inbox"))
  end

  describe "GET / 의 quick_modal 에 subject select 존재" do
    before { get "/" }

    it "subject name 의 select element 노출" do
      expect(last_response.body).to include('name="subject"')
      expect(last_response.body).to include("4축 분류")
    end

    it "4 옵션 + (없음) 모두 노출" do
      body = last_response.body
      expect(body).to include('value="person"')
      expect(body).to include('value="subject"')
      expect(body).to include('value="document"')
      expect(body).to include('value="identity"')
      expect(body).to include('value=""') # (없음)
    end
  end

  describe "POST /memos with subject param" do
    it "subject: 'person' — 정상 저장 + DB 컬럼 person" do
      post "/memos", body: "김철수 학생 관찰", subject: "person"
      expect(last_response.status).to eq(200)

      row = db[:entries].first
      expect(row[:subject]).to eq("person")
    end

    Sowing::Capture::Item::SUBJECTS.each do |axis|
      it "subject: '#{axis}' — 정상 저장 + DB ENUM" do
        post "/memos", body: "샘플 본문", subject: axis.to_s
        expect(last_response.status).to eq(200)
        expect(db[:entries].first[:subject]).to eq(axis.to_s)
      end
    end

    it "subject 미지정 (빈 문자열) — DB 에 NULL 저장" do
      post "/memos", body: "분류 없음", subject: ""
      expect(last_response.status).to eq(200)
      expect(db[:entries].first[:subject]).to be_nil
    end

    it "subject 파라미터 자체가 없음 — DB 에 NULL" do
      post "/memos", body: "param 없음"
      expect(last_response.status).to eq(200)
      expect(db[:entries].first[:subject]).to be_nil
    end

    it "잘못된 subject 값 — 422" do
      post "/memos", body: "본문", subject: "random_axis"
      expect(last_response.status).to eq(422)
      expect(db[:entries].count).to eq(0)
    end
  end

  describe "subject 별 entries 검색" do
    it "DB 의 subject 컬럼으로 필터링 가능" do
      post "/memos", body: "학생 관찰 1", subject: "person"
      post "/memos", body: "수업 메모", subject: "subject"
      post "/memos", body: "잡담 메모", subject: ""

      person_rows = db[:entries].where(subject: "person").all
      expect(person_rows.size).to eq(1)
      expect(person_rows.first[:subject]).to eq("person")
    end
  end
end
