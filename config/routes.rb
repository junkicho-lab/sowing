# frozen_string_literal: true

# 컨트롤러 마운트 + 최상위 라우트(/health 등 시스템 엔드포인트).
# 사용자 향 라우트는 각 컨트롤러가 정의하고 여기서 use로 마운트한다.

class Sowing::Application
  # 사용자 향 화면. 마운트 순서가 매칭 우선순위.
  use Sowing::Controllers::OnboardingController
  use Sowing::Controllers::TutorialController
  use Sowing::Controllers::DashboardController
  use Sowing::Controllers::MemosController
  use Sowing::Controllers::NotesController
  use Sowing::Controllers::RecordsController
  use Sowing::Controllers::TagsController
  use Sowing::Controllers::SearchController
  use Sowing::Controllers::TemplatesController
  use Sowing::Controllers::GenerateController # Phase 16 P16-T04 — 공식 양식 생성
  use Sowing::Controllers::GuidesController
  use Sowing::Controllers::SettingsController
  use Sowing::Controllers::SynthController
  use Sowing::Controllers::GraphController
  use Sowing::Controllers::PreviewController
  use Sowing::Controllers::ApiController

  # Phase 13 W25-T01 — 동사 중심 IA 통합 진입점 (/write, /plan, /mirror).
  # 기존 명사 라우트는 그대로 작동 — 두 계층 공존 (ADR-014 제안).
  # ViewController 가 /view/* 를 처리 (먼저 마운트) → NavController 는 fallback.
  use Sowing::Controllers::ViewController
  use Sowing::Controllers::PlansController
  use Sowing::Controllers::NavController

  # 시스템 헬스체크 (컨트롤러로 분리할 만한 가치 없는 단일 엔드포인트).
  get "/health" do
    content_type :json
    {status: "ok", env: Sowing.env, time: Time.now.iso8601}.to_json
  end
end
