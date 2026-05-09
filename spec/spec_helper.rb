# frozen_string_literal: true

ENV["SOWING_ENV"] = "test"

# 테스트용 임시 디렉토리 (테스트마다 격리)
require "tmpdir"
TEST_TMP = Dir.mktmpdir("sowing-test-")
ENV["SOWING_VAULT"] = File.join(TEST_TMP, "vault")
ENV["SOWING_DATA_DIR"] = File.join(TEST_TMP, "data")

require "bundler/setup"
require_relative "../config/application"

require "rspec"
require "rspec/its"
require "factory_bot"
require "timecop"

# 마이그레이션 실행
require "sequel/core"
Sequel.extension :migration
Sequel::Migrator.run(Sowing::Infrastructure::DB.connection, "db/migrations")

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = false
  config.default_formatter = "doc" if config.files_to_run.one?
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  config.before(:each) do
    # 각 테스트 시작 시 시간 freeze 옵션 활성화 가능
    # Timecop.freeze(Time.parse("2026-05-07 09:00:00 +0900"))

    # W7-T01: 기본적으로 온보딩을 완료 상태로 — 기존 spec이 redirect로 깨지지 않게.
    # 온보딩 자체를 검증하는 spec은 명시적으로 Settings.reset!를 호출.
    Sowing::Infrastructure::Settings.update(onboarding_completed: true)

    # W9-T01: audit log 격리 — 각 spec 시작 시 빈 상태에서 시작.
    Sowing::Infrastructure::AuditLog.instance.clear!
  end

  config.after(:each) do
    Timecop.return
  end

  config.after(:suite) do
    require "fileutils"
    FileUtils.rm_rf(TEST_TMP) if File.exist?(TEST_TMP)
  end
end
