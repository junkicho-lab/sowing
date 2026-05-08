# frozen_string_literal: true

require "bundler/setup"
require_relative "config/application"

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :db do
  desc "마이그레이션 실행"
  task :migrate do
    require "sequel/core"
    Sequel.extension :migration
    Sowing.boot_db!
    Sequel::Migrator.run(Sowing::Infrastructure::DB.connection, "db/migrations")
    puts "✅ Migration 완료"
  end

  desc "마지막 마이그레이션 롤백"
  task :rollback do
    require "sequel/core"
    Sequel.extension :migration
    Sowing.boot_db!
    current = Sequel::Migrator.get_current_migration_version(Sowing::Infrastructure::DB.connection)
    Sequel::Migrator.run(Sowing::Infrastructure::DB.connection, "db/migrations", target: current - 1)
    puts "↩️  Rollback 완료"
  end

  desc "DB 초기화 (인덱스만 삭제, 마크다운 보존)"
  task :reset do
    require "fileutils"
    Sowing.boot_paths!
    db_path = Sowing::Infrastructure::Paths.db_path
    if File.exist?(db_path)
      FileUtils.rm(db_path)
      puts "🗑  #{db_path} 삭제"
    end
    Rake::Task["db:migrate"].invoke
    puts "✅ DB 재생성 완료"
  end

  desc "초기 셋업 (디렉토리 + 마이그레이션)"
  task :setup do
    Sowing.boot_paths!
    Sowing::Infrastructure::Paths.ensure_data_dirs!
    Rake::Task["db:migrate"].invoke
    puts "✅ Setup 완료"
  end
end

namespace :vault do
  desc "전체 볼트 재인덱싱 (ConsistencyCheck 활용 — 인덱스 wipe 후 재구축)"
  task :reindex do
    Sowing.boot!
    coordinator = Sowing::Sync::Coordinator.new(vault_dir: Sowing::Infrastructure::Paths.vault_dir)
    summary = Sowing::Sync::ConsistencyCheck.new(
      vault_dir: Sowing::Infrastructure::Paths.vault_dir,
      index_repo: Sowing::Repositories::IndexRepo.new,
      coordinator: coordinator
    ).run
    puts "✅ 재인덱싱 완료 — unchanged #{summary.unchanged} / reindexed #{summary.reindexed} / added #{summary.added} / adopted #{summary.adopted} / removed #{summary.removed} / errors #{summary.errors.size}"
  end

  desc "샘플 콘텐츠 12종 시드 (templates/samples/ → vault). 중복은 자동 스킵."
  task :seed do
    Sowing.boot!
    result = Sowing::UseCases::SeedSamples.new.call
    if result.success?
      data = result.value!
      puts "🌱 샘플 시드 — 신규 #{data[:seeded]}건 / 중복 스킵 #{data[:skipped]}건 / 전체 #{data[:total]}건"
    else
      puts "⚠ 시드 실패: #{result.failure}"
      exit 1
    end
  end
end
