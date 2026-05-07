# frozen_string_literal: true

require "bundler/setup"
require "zeitwerk"
require "sinatra/base"
require "sequel"

# Sowing 모듈 진입점
module Sowing
  class << self
    attr_accessor :loader, :env, :logger

    # 앱 전체 부트스트랩 (paths + db + 자동 로딩)
    def boot!
      boot_paths!
      boot_loader!
      boot_db!
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
        "db" => "DB"
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

    enable :sessions
    set :session_secret, ENV.fetch("SOWING_SESSION_SECRET") {
      # 개발 환경에서는 데이터 디렉토리에 자동 생성·보관
      Sowing::Infrastructure::Paths.session_secret
    }

    # 라우트는 별도 파일에서 로드
    require_relative "routes"
  end
end
