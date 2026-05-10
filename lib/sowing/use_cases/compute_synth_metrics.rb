# frozen_string_literal: true

require "date"
require "dry/monads"
require "json"
require "pathname"
require "time"

module Sowing
  module UseCases
    # 합성기 사용 지표 집계 — 베타 사용자 검증 인프라.
    #
    # ROADMAP Phase 11/12 마일스톤 측정 도구:
    #   - 학생 디제스트 사용자 수락률 (Phase 11 마일스톤 ≥ 50%)
    #   - 합성 type 별 활용 분포 (Phase 12 베타 사용자 회고 데이터 기반)
    #
    # 입력 소스: vault/.sowing/audit.log (JSON Lines, append-only)
    #   - synth_generate / synth_accept / synth_reject 이벤트만 필터
    #   - path 필드에서 type 추출 (".sowing/synth/{type}/{slug}.md")
    #
    # 출력:
    #   {
    #     totals: {generate, accept, reject, pending, acceptance_rate},
    #     by_type: {students: {...}, reflections: {...}, ...},
    #     by_week: [{week: "2026-W19", generate, accept, reject}, ...],
    #     first_event_at, last_event_at, duration_days
    #   }
    #
    # 멱등 — read-only. vault·DB 변경 없음.
    class ComputeSynthMetrics
      include Dry::Monads[:result]

      SYNTH_ACTIONS = %w[synth_generate synth_accept synth_reject].freeze
      PATH_RE = %r{\A\.sowing/synth/(?<type>[^/]+)/(?<slug>.+)\.md\z}

      def initialize(audit_log: nil, clock: Time)
        @audit_log = audit_log || Infrastructure::AuditLog.instance
        @clock = clock
      end

      # @param since [Time, String, nil] 시작 시점. nil = 모든 이력
      # @param until_time [Time, String, nil] 종료 시점. nil = now
      # @return [Result] Success(Hash) | Failure(:no_events)
      def call(since: nil, until_time: nil)
        until_t = parse_time(until_time) || @clock.now
        since_t = parse_time(since)  # nil 허용 — 시작 무한대

        all_events = @audit_log.read_all
        synth_events = all_events.select { |e| SYNTH_ACTIONS.include?(e["action"]) }
        synth_events = filter_by_time(synth_events, since_t, until_t)

        return Failure(:no_events) if synth_events.empty?

        events_with_meta = synth_events.map { |e| enrich(e) }

        Success({
          totals: compute_totals(events_with_meta),
          by_type: compute_by_type(events_with_meta),
          by_week: compute_by_week(events_with_meta),
          first_event_at: parse_time(events_with_meta.first["ts"]),
          last_event_at: parse_time(events_with_meta.last["ts"]),
          duration_days: duration_days(events_with_meta),
          period_since: since_t,
          period_until: until_t,
          event_count: events_with_meta.size
        })
      end

      private

      def parse_time(value)
        return nil if value.nil?
        return value if value.is_a?(Time)
        Time.parse(value.to_s)
      end

      def filter_by_time(events, since_t, until_t)
        events.select { |e|
          ts = parse_time(e["ts"])
          next false if ts.nil?
          (since_t.nil? || ts >= since_t) && ts <= until_t
        }
      end

      # path 에서 type 추출 — accept 의 경우 entry_id 가 새 Record ULID 이라 path 만 신뢰.
      def enrich(event)
        m = event["path"].to_s.match(PATH_RE)
        event.merge("synth_type" => m ? m[:type] : "unknown",
          "synth_slug" => m ? m[:slug] : nil)
      end

      def compute_totals(events)
        counts = events.group_by { |e| e["action"] }.transform_values(&:size)
        gen = counts["synth_generate"] || 0
        acc = counts["synth_accept"] || 0
        rej = counts["synth_reject"] || 0
        decided = acc + rej
        # Pending = 생성됐지만 아직 수락/거절 결정 안 된 것 — 음수 가능 (재생성 시 generate 가 누적됨).
        pending = [gen - decided, 0].max
        rate = (decided > 0) ? acc.to_f / decided : nil
        {
          generate: gen, accept: acc, reject: rej, pending: pending,
          decided: decided, acceptance_rate: rate
        }
      end

      def compute_by_type(events)
        by_type = events.group_by { |e| e["synth_type"] }
        by_type.transform_values { |type_events|
          counts = type_events.group_by { |e| e["action"] }.transform_values(&:size)
          gen = counts["synth_generate"] || 0
          acc = counts["synth_accept"] || 0
          rej = counts["synth_reject"] || 0
          decided = acc + rej
          {
            generate: gen, accept: acc, reject: rej,
            pending: [gen - decided, 0].max,
            acceptance_rate: (decided > 0) ? acc.to_f / decided : nil
          }
        }
      end

      def compute_by_week(events)
        by_week = events.group_by { |e|
          ts = parse_time(e["ts"])
          d = ts.to_date
          format("%04d-W%02d", d.cwyear, d.cweek)
        }
        by_week.sort.map { |week, week_events|
          counts = week_events.group_by { |e| e["action"] }.transform_values(&:size)
          {
            week: week,
            generate: counts["synth_generate"] || 0,
            accept: counts["synth_accept"] || 0,
            reject: counts["synth_reject"] || 0
          }
        }
      end

      def duration_days(events)
        first = parse_time(events.first["ts"]).to_date
        last = parse_time(events.last["ts"]).to_date
        (last - first).to_i + 1
      end
    end
  end
end
