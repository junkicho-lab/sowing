# frozen_string_literal: true

# 컨트롤러 마운트 + 최상위 라우트(/health 등 시스템 엔드포인트).
# 사용자 향 라우트는 각 컨트롤러가 정의하고 여기서 use로 마운트한다.

class Sowing::Application
  # 사용자 향 화면. 마운트 순서가 매칭 우선순위.
  use Sowing::Controllers::DashboardController
  use Sowing::Controllers::MemosController
  use Sowing::Controllers::NotesController
  use Sowing::Controllers::RecordsController
  use Sowing::Controllers::PreviewController

  # 시스템 헬스체크 (컨트롤러로 분리할 만한 가치 없는 단일 엔드포인트).
  get "/health" do
    content_type :json
    {status: "ok", env: Sowing.env, time: Time.now.iso8601}.to_json
  end
end
