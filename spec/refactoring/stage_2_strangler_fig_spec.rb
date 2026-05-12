# frozen_string_literal: true

require "rack/test"
require "fileutils"

# Phase R Stage 2 R2-T04 — Strangler Fig.
# POST /memos 가 UseCases::CreateMemo 대신 Sowing::Capture.create_item 으로 위임됨을 검증.
#
# 검증 방식:
#   1. Capture::ItemRepo 에 spy 를 주입하여 .create 가 호출되는지 관찰
#   2. CreateMemo Use Case 가 호출되지 않는지 (spec 격리 — 옛 경로 미사용)
#   3. 저장된 entry 가 Capture::Item 형태로 round-trip 가능
RSpec.describe "Strangler Fig — POST /memos → Sowing::Capture (Stage 2 R2-T04)" do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:links].delete
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete
    vault = Sowing::Core::Paths.vault_dir
    FileUtils.rm_rf(vault.join("00_Inbox"))
  end

  after do
    Sowing::Capture.reset_repo!
  end

  describe "POST /memos 가 Sowing::Capture.create_item 을 호출" do
    it "Capture::ItemRepo#create 가 정확히 1번 호출됨 (옛 CreateMemo 미경유)" do
      spy_repo = instance_double(Sowing::Capture::ItemRepo)
      sample_item = Sowing::Capture::Item.new(
        id: Sowing::Domain::ValueObjects::Ulid.generate,
        body: "본문",
        created_at: Time.now
      )
      expect(spy_repo).to receive(:create).with(an_instance_of(Sowing::Capture::Item))
        .once.and_return(sample_item)
      Sowing::Capture.repo = spy_repo

      post "/memos", body: "본문"
      expect(last_response.status).to eq(200)
    end

    it "CreateMemo Use Case 는 더 이상 호출되지 않음" do
      # 옛 경로 차단 검증 — UseCases::CreateMemo.new 가 호출되지 않아야 함
      expect(Sowing::UseCases::CreateMemo).not_to receive(:new)
      post "/memos", body: "본문"
      expect(last_response.status).to eq(200)
    end
  end

  describe "저장된 entry 의 BC 신원" do
    it "Capture.find 로 Item 으로 회수 가능" do
      post "/memos", body: "Strangler 검증 본문"
      expect(last_response.status).to eq(200)

      row = db[:entries].first
      expect(row[:mode]).to eq("memo") # 파일·DB mode 는 :memo 유지 (Strangler 호환)

      item = Sowing::Capture.find(row[:id])
      expect(item).to be_a(Sowing::Capture::Item)
      expect(item.body).to eq("Strangler 검증 본문")
    end
  end

  describe "에러 경로 — 빈 body 422" do
    it "Capture.create_item 의 ArgumentError → 422 + empty_body 메시지" do
      post "/memos", body: ""
      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("본문을 입력")
    end
  end
end
