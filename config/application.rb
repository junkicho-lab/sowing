# frozen_string_literal: true

# 한국어·옵시디언 마크다운 호환성을 위해 외부 인코딩을 UTF-8로 강제 (ADR-012).
# 시스템 locale이 C/POSIX인 환경(Tebako 패키징, Docker, 일부 CI)에서도 일관성 보장.
# default_internal은 의도적으로 nil 유지 — 입력 자동 변환 비활성화로 비-UTF-8 외부 파일을
# 만났을 때 즉시 raise 하지 않고 permissive 처리.
Encoding.default_external = Encoding::UTF_8

require "bundler/setup"
require "zeitwerk"
require "sinatra/base"
require "sequel"

# json-schema (mcp gem 의존)의 MultiJSON 폴백 중단 — 표준 stdlib JSON 사용으로 deprecation 메시지 침묵.
require "json-schema"
JSON::Validator.use_multi_json = false

# Sowing 모듈 진입점
module Sowing
  class << self
    attr_accessor :loader, :env, :logger, :sync_coordinator

    # 앱 전체 부트스트랩 (paths + db + 자동 로딩)
    def boot!
      boot_dotenv!
      boot_paths!
      boot_loader!
      boot_db!
    end

    # 프로젝트 루트의 .env / .env.local 을 ENV 에 머지 (시스템 ENV 우선).
    # boot 가장 앞에 와야 함 — 이후 단계 (Paths, Logger 등) 가 ENV 를 읽을 수 있도록.
    # Zeitwerk 로드 전이라 require_relative 로 직접 로드.
    def boot_dotenv!
      require_relative "../lib/sowing/infrastructure/dotenv"
      Sowing::Infrastructure::Dotenv.load(root)
    end

    # 동기화 부팅 — 볼트 ↔ 인덱스 일관성 검증 후 watcher 시작 (W5-T04).
    # 무거운 I/O 동반(Listen 스레드 + 전체 볼트 스캔)이므로 boot!에서 분리, 명시 호출만.
    # CLI/서버 진입점에서 한 번 호출. 테스트는 호출하지 않음.
    # @return [Sowing::Sync::Coordinator] 시작된 코디네이터
    def boot_sync!
      return @sync_coordinator if @sync_coordinator&.running?

      vault_dir = Sowing::Infrastructure::Paths.vault_dir
      coordinator = Sowing::Sync::Coordinator.new(vault_dir: vault_dir, logger: @logger)
      Sowing::Sync::ConsistencyCheck.new(
        vault_dir: vault_dir,
        index_repo: Sowing::Repositories::IndexRepo.new,
        coordinator: coordinator
      ).run
      coordinator.start
      @sync_coordinator = coordinator
    end

    def boot_paths!
      @env ||= ENV["SOWING_ENV"] || "development"
      # Paths 모듈은 Zeitwerk 로드 전에 require 필요
      require_relative "../lib/sowing/infrastructure/paths"
      Sowing::Infrastructure::Paths.ensure_data_dirs!
    end

    def boot_loader!
      return if @loader

      @loader = Zeitwerk::Loader.new
      @loader.push_dir(File.expand_path("../lib/sowing", __dir__), namespace: Sowing)

      # 약어 처리 (Zeitwerk가 모듈명을 추론하지 못하는 경우)
      @loader.inflector.inflect(
        "ulid" => "Ulid",
        "fts_query" => "FtsQuery",
        "db" => "DB",
        "version" => "VERSION",
        "mcp" => "MCP",
        "openai" => "OpenAI"
      )

      @loader.setup
    end

    def boot_db!
      boot_paths!
      Sowing::Infrastructure::DB.connect!
    end

    def root
      File.expand_path("..", __dir__)
    end
  end
end

# 즉시 부트
Sowing.boot!

# Sinatra 앱 정의
module Sowing
  class Application < Sinatra::Base
    set :root, Sowing.root
    set :views, File.join(Sowing.root, "views")
    set :public_folder, File.join(Sowing.root, "public")
    set :bind, "127.0.0.1"
    set :port, ENV.fetch("SOWING_PORT", "48723").to_i
    set :show_exceptions, :after_handler if development?

    # HTML form은 GET·POST만 보낼 수 있으므로 _method=patch/delete hidden 필드로 모듈러 매칭.
    # Rack::MethodOverride 미들웨어가 자동 추가됨 (sub-controller에도 효과 적용).
    set :method_override, true

    enable :sessions
    set :session_secret, ENV.fetch("SOWING_SESSION_SECRET") {
      # 개발 환경에서는 데이터 디렉토리에 자동 생성·보관
      Sowing::Infrastructure::Paths.session_secret
    }

    # 라우트는 별도 파일에서 로드
    require_relative "routes"
  end
end
