# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Sowing
  module Eval
    # Eval 결과 영속화 (W13-T03).
    #
    # 위치: eval/results/{ISO8601-ish}.json — git 에 커밋되어 회귀 추적 base.
    # 한 파일 = 한 run 의 전체 결과 (run_id, backend, summary, per-case scores).
    #
    # latest_summary / compare_to_previous 로 회귀 감지 — 차원별 평균이 임계값 이상
    # 떨어지면 CI fail.
    class ResultStore
      DEFAULT_DIR = "eval/results"
      DEFAULT_REGRESSION_THRESHOLD = 0.5 # 차원 평균 0.5 이상 하락 시 회귀

      def initialize(root: nil)
        @root = root ? Pathname.new(root.to_s).expand_path : default_root
      end

      attr_reader :root

      def save(payload)
        FileUtils.mkdir_p(@root)
        run_id = payload["run_id"] || payload[:run_id] || Time.now.iso8601
        # 파일명 안전 — 콜론은 일부 파일시스템에서 문제.
        slug = run_id.tr(":", "-")
        path = @root.join("#{slug}.json")
        File.write(path, JSON.pretty_generate(payload))
        path
      end

      # 모든 결과 (시간 오름차순).
      def all
        return [] unless @root.exist?
        Dir.glob(@root.join("*.json")).sort.map { |p| JSON.parse(File.read(p)) }
      end

      def latest
        all.last
      end

      def previous
        runs = all
        return nil if runs.size < 2
        runs[-2]
      end

      # 회귀 감지 — 마지막 결과 vs 직전 결과.
      # @return [Hash] { regressed: Bool, dimensions: { dim => { current:, previous:, delta: } } }
      def compare_to_previous(threshold: DEFAULT_REGRESSION_THRESHOLD)
        current = latest
        previous = self.previous
        return {regressed: false, reason: "비교할 직전 결과 없음", dimensions: {}} if current.nil? || previous.nil?

        dims = {}
        regressed = false

        all_dim_keys(current, previous).each do |dim|
          cur_avg = current.dig("summary", dim, "avg")
          prev_avg = previous.dig("summary", dim, "avg")
          next if cur_avg.nil? || prev_avg.nil?

          delta = cur_avg - prev_avg
          dims[dim] = {current: cur_avg, previous: prev_avg, delta: delta.round(3)}
          regressed = true if delta < -threshold
        end

        {regressed: regressed, dimensions: dims, threshold: threshold}
      end

      private

      def default_root
        Pathname.new(File.expand_path("../../../../#{DEFAULT_DIR}", __FILE__))
      end

      def all_dim_keys(current, previous)
        ((current["summary"] || {}).keys + (previous["summary"] || {}).keys).uniq
      end
    end
  end
end
