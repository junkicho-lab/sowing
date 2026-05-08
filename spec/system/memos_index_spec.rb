# frozen_string_literal: true

require "rack/test"
require "fileutils"

RSpec.describe "GET /memos (메모 목록)", type: :request do
  include Rack::Test::Methods

  let(:db) { Sowing::Infrastructure::DB.connection }
  let(:vault_dir) { Sowing::Infrastructure::Paths.vault_dir }

  def app
    Sowing::Application
  end

  before do
    header "Host", "127.0.0.1"
    db[:entry_tags].delete
    db[:tags].delete
    db[:entries].delete
    FileUtils.rm_rf(vault_dir.join("00_Inbox"))
  end

  def create_memo(body)
    post "/memos", body: body
  end

  describe "메모가 없을 때" do
    before { get "/memos" }

    it "200 OK + 빈 상태 안내를 반환한다" do
      expect(last_response).to be_ok
      expect(last_response.body).to include("아직 작성된 메모가 없습니다")
    end

    it "총 0건임을 표시한다" do
      expect(last_response.body).to include("총 0건")
    end

    it "페이지네이션은 표시하지 않는다 (총 페이지 1 ≤ 1)" do
      expect(last_response.body).not_to include("pagination__link")
    end
  end

  describe "메모가 있을 때" do
    before do
      ["첫 번째 메모", "두 번째 메모", "세 번째 메모"].each { |b| create_memo(b) }
      get "/memos"
    end

    it "총 건수가 정확하다" do
      expect(last_response.body).to include("총 3건")
    end

    it "메모 카드들이 created_at 내림차순으로 표시된다" do
      body = last_response.body
      idx_3 = body.index("세 번째 메모")
      idx_2 = body.index("두 번째 메모")
      idx_1 = body.index("첫 번째 메모")
      expect(idx_3).to be < idx_2
      expect(idx_2).to be < idx_1
    end

    it "단일 페이지면 페이지네이션이 표시되지 않는다 (3 < 30)" do
      expect(last_response.body).not_to include("pagination__link")
    end
  end

  describe "페이지네이션 (≥ 31건)" do
    before do
      31.times { |i| create_memo("메모 #{i + 1}") }
      get "/memos"
    end

    it "1페이지에 30건이 표시된다" do
      expect(last_response.body.scan('class="memo-card"').size).to eq(30)
    end

    it "1 / 2 페이지 인디케이터가 보인다" do
      expect(last_response.body).to include("1 / 2")
    end

    it "다음 링크는 활성, 이전 링크는 비활성이다" do
      expect(last_response.body).to include('href="/memos?page=2"')
      expect(last_response.body).to include('aria-disabled="true"')
    end

    it "?page=2 로 이동하면 2페이지가 보인다" do
      get "/memos?page=2"
      expect(last_response.body).to include("2 / 2")
      expect(last_response.body).to include('href="/memos?page=1"')
      expect(last_response.body.scan('class="memo-card"').size).to eq(1)
    end

    it "범위를 벗어난 page는 빈 페이지지만 200 OK이다" do
      get "/memos?page=99"
      expect(last_response).to be_ok
      expect(last_response.body).to include("이 페이지에 메모가 없습니다")
      expect(last_response.body).to include("첫 페이지로")
    end

    it "page=0 같은 잘못된 값은 1로 보정된다 (clamp)" do
      get "/memos?page=0"
      expect(last_response.body).to include("1 / 2")
    end
  end

  describe "성능 게이트 (100건 < 200ms)" do
    it "100건의 메모가 있어도 응답이 200ms 미만이다" do
      100.times { |i| create_memo("성능 테스트 메모 #{i + 1}") }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      get "/memos"
      elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

      expect(last_response).to be_ok
      expect(last_response.body).to include("총 100건")
      expect(elapsed_ms).to be < 200,
        "GET /memos took #{elapsed_ms.round(1)}ms (target < 200ms)"
    end
  end

  describe "내비게이션" do
    it "헤더에 '메모' 링크가 있고 /memos를 가리킨다" do
      get "/"
      expect(last_response.body).to include('<a href="/memos">메모</a>')
    end
  end
end
