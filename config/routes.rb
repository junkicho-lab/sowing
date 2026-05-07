# frozen_string_literal: true

# Sinatra 라우트 정의.
# 컨트롤러가 추가되면 각 컨트롤러를 mount 한다.
#
# 작업 단위로 컨트롤러가 추가될 때, 본 파일에 등록한다:
#
#   use Sowing::Controllers::DashboardController
#   use Sowing::Controllers::MemosController
#   ...

class Sowing::Application
  get "/" do
    "Hello, Sowing 🌱"
  end

  get "/health" do
    content_type :json
    { status: "ok", env: Sowing.env, time: Time.now.iso8601 }.to_json
  end
end
