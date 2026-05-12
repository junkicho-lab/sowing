# frozen_string_literal: true

require "rack/test"
require "fileutils"

# 2026-05-12 — Record 의 category 를 자유 텍스트에서 4축 한국어 라벨 ENUM 으로 제한.
# UI (radio button) 에서만 강제 — 도메인 validator 는 기존 자유 텍스트도 허용 (호환).
RSpec.describe "Record 카테고리 4축 제한 (UI)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Core::DB.connection }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries_fts].delete
    db[:entries].delete
    FileUtils.rm_rf(Sowing::Core::Paths.vault_dir.join("30_Records"))
  end

  describe "GET /records/new — 4 radio button 노출" do
    before { get "/records/new" }

    it "4축 라벨 (인물·교과·문서·정체성) 모두 노출" do
      %w[인물 교과 문서 정체성].each do |label|
        expect(last_response.body).to match(%r{<input type="radio" name="category" value="#{label}"})
      end
    end

    it "옛 자유 텍스트 input 미노출" do
      expect(last_response.body).not_to include('<input type="text"
           id="record_category"')
    end

    it "4 라벨 외의 radio 옵션 없음" do
      # 5번째 옵션 (예: '학생기록') 이 없는지 검증
      expect(last_response.body).not_to include('value="학생기록"')
      expect(last_response.body).not_to include('value="수업기록"')
    end
  end

  describe "POST /records — 4축 카테고리로 저장" do
    %w[인물 교과 문서 정체성].each do |label|
      it "category=#{label} 정상 저장" do
        post "/records",
          "title" => "샘플 #{label} 기록",
          "body" => "본문",
          "category" => label
        expect(last_response.status).to be_between(302, 303)
        expect(db[:entries].first[:category]).to eq(label)
      end
    end
  end

  describe "빠른 기록 모달 — 4 radio button 노출" do
    before { get "/" }

    it "4축 라벨 모두 노출 (modal 안)" do
      body = last_response.body
      expect(body).to include('id="quick_record_modal"')
      %w[인물 교과 문서 정체성].each do |label|
        expect(body).to match(%r{<input type="radio" name="category" value="#{label}"})
      end
    end

    it "옛 datalist 자동완성 미노출 (자유 텍스트 폐기)" do
      expect(last_response.body).not_to include('id="quick_record_category_list"')
    end
  end

  describe "Insight ACCEPT_CATEGORY — 18 type 모두 4축으로 매핑" do
    it "모든 ACCEPT_CATEGORY 값이 4축 한국어 라벨" do
      valid = %w[인물 교과 문서 정체성]
      Sowing::Insight::ACCEPT_CATEGORY.each do |type, cat|
        expect(valid).to include(cat), "Type #{type.inspect} 의 ACCEPT_CATEGORY=#{cat.inspect} 가 4축 외 값"
      end
    end

    it "각 4축에 최소 1개 type 매핑됨 (균형 검증)" do
      counts = Sowing::Insight::ACCEPT_CATEGORY.values.tally
      %w[인물 교과 문서 정체성].each do |label|
        expect(counts).to have_key(label), "4축 #{label} 에 매핑된 synth type 없음"
        expect(counts[label]).to be > 0
      end
    end
  end
end
