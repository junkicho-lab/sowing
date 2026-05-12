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
    Sequel::Migrator.run(Sowing::Core::DB.connection, "db/migrations")
    puts "✅ Migration 완료"
  end

  desc "마지막 마이그레이션 롤백"
  task :rollback do
    require "sequel/core"
    Sequel.extension :migration
    Sowing.boot_db!
    current = Sequel::Migrator.get_current_migration_version(Sowing::Core::DB.connection)
    Sequel::Migrator.run(Sowing::Core::DB.connection, "db/migrations", target: current - 1)
    puts "↩️  Rollback 완료"
  end

  desc "DB 초기화 (인덱스만 삭제, 마크다운 보존)"
  task :reset do
    require "fileutils"
    Sowing.boot_paths!
    db_path = Sowing::Core::Paths.db_path
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
    Sowing::Core::Paths.ensure_data_dirs!
    Rake::Task["db:migrate"].invoke
    puts "✅ Setup 완료"
  end
end

namespace :vault do
  desc "전체 볼트 재인덱싱 (ConsistencyCheck 활용 — 인덱스 wipe 후 재구축)"
  task :reindex do
    Sowing.boot!
    coordinator = Sowing::Sync::Coordinator.new(vault_dir: Sowing::Core::Paths.vault_dir)
    summary = Sowing::Sync::ConsistencyCheck.new(
      vault_dir: Sowing::Core::Paths.vault_dir,
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

namespace :eval do
  desc "Eval 코퍼스 전체 평가 (W13-T03). SOWING_EVAL_BACKEND=fake|openai|anthropic|ollama 로 백엔드 선택. 기본 fake."
  task :run do
    Sowing.boot!
    backend = build_eval_backend
    runner = Sowing::Eval::Runner.new(backend: backend)
    payload = runner.run

    store = Sowing::Eval::ResultStore.new
    path = store.save(payload)
    summary = payload["summary"]

    puts "✅ Eval 완료 — backend=#{backend.name} model=#{payload["model"]}"
    puts "   corpus_size=#{payload["corpus_size"]}, 결과: #{path}"
    puts "   차원별 평균:"
    summary.sort.each do |dim, stats|
      puts "     #{dim.ljust(20)} avg=#{stats["avg"]} (#{stats["min"]}~#{stats["max"]}, n=#{stats["n"]})"
    end

    # 회귀 감지
    diff = store.compare_to_previous
    if diff[:dimensions].empty?
      puts "ℹ  비교할 직전 결과 없음 (첫 실행)"
    else
      puts "📉 회귀 비교 (이전 vs 현재, threshold=#{diff[:threshold]}):"
      diff[:dimensions].sort.each do |dim, info|
        marker =
          if info[:delta] < -diff[:threshold] then "❌"
          elsif info[:delta] < 0 then "⚠ "
          else "✅"
          end
        puts "   #{marker} #{dim.ljust(20)} #{info[:previous]} → #{info[:current]} (Δ #{info[:delta].round(3)})"
      end
      if diff[:regressed]
        puts "❌ 회귀 감지 — 차원 평균 하락 ≥ #{diff[:threshold]}"
        exit 1
      end
    end
  end

  desc "Eval 결과 목록 (eval/results/*.json)"
  task :list do
    Sowing.boot!
    store = Sowing::Eval::ResultStore.new
    runs = store.all
    if runs.empty?
      puts "(eval 결과 없음 — bundle exec rake eval:run 실행)"
    else
      puts "📊 #{runs.size}개 결과:"
      runs.each do |r|
        puts "  #{r["run_id"]}  backend=#{r["backend"]}  model=#{r["model"]}  size=#{r["corpus_size"]}"
      end
    end
  end

  def build_eval_backend
    case (ENV["SOWING_EVAL_BACKEND"] || "fake").downcase
    when "openai" then Sowing::Eval::Backends::OpenAI.new
    when "anthropic" then Sowing::Eval::Backends::Anthropic.new
    when "ollama" then Sowing::Eval::Backends::Ollama.new
    else Sowing::Eval::Backends::FakeBackend.new
    end
  end
end

namespace :stats do
  desc "합성기 사용 지표 (audit.log 기반). SOWING_SINCE / SOWING_UNTIL 로 기간 지정 가능 (ISO8601)."
  task :synth_metrics do
    Sowing.boot!
    use_case = Sowing::UseCases::ComputeSynthMetrics.new
    result = use_case.call(
      since: ENV["SOWING_SINCE"],
      until_time: ENV["SOWING_UNTIL"]
    )
    if result.failure?
      puts "ℹ  합성 이벤트 없음 (audit.log 에 synth_* action 없음)."
      puts "   /synth 에서 디제스트 생성·수락·거절 후 재실행."
      exit 0
    end

    m = result.value!
    puts "📊 합성기 사용 지표"
    puts "─" * 60
    puts "기간: #{m[:first_event_at].to_s[0, 10]} ~ #{m[:last_event_at].to_s[0, 10]} (#{m[:duration_days]}일)"
    puts "총 이벤트: #{m[:event_count]}건"
    puts ""

    t = m[:totals]
    rate_str = t[:acceptance_rate] ? "#{(t[:acceptance_rate] * 100).round(1)}%" : "(결정된 이벤트 없음)"
    puts "[전체]"
    puts "  생성: #{t[:generate]} · 수락: #{t[:accept]} · 거절: #{t[:reject]} · 검토 대기: #{t[:pending]}"
    puts "  수락률: #{rate_str} (Phase 11 마일스톤 ≥ 50%)"
    puts ""

    puts "[Type 별]"
    m[:by_type].sort.each do |type, stats|
      rate = stats[:acceptance_rate] ? "#{(stats[:acceptance_rate] * 100).round(1)}%" : "—"
      puts "  #{type.ljust(16)} 생성 #{stats[:generate].to_s.rjust(3)} · 수락 #{stats[:accept].to_s.rjust(3)} · 거절 #{stats[:reject].to_s.rjust(3)} · 대기 #{stats[:pending].to_s.rjust(3)} · 수락률 #{rate}"
    end
    puts ""

    if m[:by_week].any?
      puts "[주별 (최근 8주)]"
      m[:by_week].last(8).each do |w|
        bar_g = "▌" * w[:generate]
        puts "  #{w[:week]} 생성 #{bar_g} #{w[:generate]} · 수락 #{w[:accept]} · 거절 #{w[:reject]}"
      end
    end
  end

  desc "베타 사용자 리포트 (마크다운, stdout). SOWING_SINCE / SOWING_UNTIL 로 기간 지정."
  task :beta_report do
    Sowing.boot!
    result = Sowing::UseCases::ComputeSynthMetrics.new.call(
      since: ENV["SOWING_SINCE"],
      until_time: ENV["SOWING_UNTIL"]
    )
    if result.failure?
      puts "# 베타 리포트\n\n_합성 이벤트 없음._"
      next
    end

    m = result.value!
    t = m[:totals]
    puts "# Sowing 베타 사용 리포트"
    puts ""
    puts "**기간**: #{m[:first_event_at].to_s[0, 10]} ~ #{m[:last_event_at].to_s[0, 10]} (#{m[:duration_days]}일)"
    puts ""
    puts "## 전체 지표"
    puts ""
    puts "| 지표 | 값 |"
    puts "|------|-----|"
    puts "| 합성 생성 | #{t[:generate]} |"
    puts "| 수락 | #{t[:accept]} |"
    puts "| 거절 | #{t[:reject]} |"
    puts "| 검토 대기 | #{t[:pending]} |"
    puts "| **수락률** | #{t[:acceptance_rate] ? "**#{(t[:acceptance_rate] * 100).round(1)}%**" : "—"} |"
    puts ""
    puts "**Phase 11 마일스톤 평가**: 수락률 #{(t[:acceptance_rate] && t[:acceptance_rate] >= 0.5) ? "✅ 50% 달성" : "🟡 50% 미달성"}"
    puts ""
    puts "## Type 별 활용"
    puts ""
    puts "| Type | 생성 | 수락 | 거절 | 대기 | 수락률 |"
    puts "|------|------|------|------|------|--------|"
    m[:by_type].sort.each do |type, s|
      rate = s[:acceptance_rate] ? "#{(s[:acceptance_rate] * 100).round(1)}%" : "—"
      puts "| #{type} | #{s[:generate]} | #{s[:accept]} | #{s[:reject]} | #{s[:pending]} | #{rate} |"
    end
    puts ""
    puts "## 주별 추이"
    puts ""
    puts "| 주 | 생성 | 수락 | 거절 |"
    puts "|----|------|------|------|"
    m[:by_week].each { |w| puts "| #{w[:week]} | #{w[:generate]} | #{w[:accept]} | #{w[:reject]} |" }
  end
end
