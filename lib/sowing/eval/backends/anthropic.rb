# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Sowing
  module Eval
    module Backends
      # Anthropic Messages API 백엔드 (W13-T02).
      #
      # ENV: ANTHROPIC_API_KEY 필수. 모델 기본 Claude Haiku 4.5 (저비용·빠름).
      # 모델 변경: Anthropic.new(model: "claude-sonnet-4-5-20250929") 등.
      # Net::HTTP 만 사용 (외부 gem 0).
      class Anthropic < Base
        # 사용자 노출 모델 카탈로그 (UI 드롭다운 + allowlist 검증의 SoT).
        # 비용은 Anthropic 공시 단가 (2025년 기준, USD per million tokens).
        # 합성기 1건 추정 비용 = input(~3K) × in_per_mtok / 1M + output(~1K) × out_per_mtok / 1M.
        # 비용은 변동 가능 — Anthropic Pricing 페이지가 source of truth.
        MODELS = {
          "claude-haiku-4-5-20251001" => {
            label: "Haiku 4.5",
            tier: "저비용·빠름 (기본)",
            in_per_mtok: 1.00,
            out_per_mtok: 5.00,
            speed_seconds: "2~5"
          },
          "claude-sonnet-4-5-20250929" => {
            label: "Sonnet 4.5",
            tier: "균형 (품질·속도)",
            in_per_mtok: 3.00,
            out_per_mtok: 15.00,
            speed_seconds: "5~10"
          },
          "claude-opus-4-7" => {
            label: "Opus 4.7",
            tier: "최고품질 (느림·고비용)",
            in_per_mtok: 15.00,
            out_per_mtok: 75.00,
            speed_seconds: "15~30"
          }
        }.freeze

        DEFAULT_MODEL = "claude-haiku-4-5-20251001"
        BASE_URL = "https://api.anthropic.com/v1/messages"
        API_VERSION = "2023-06-01"

        # 합성 1건 추정 비용 (USD). UI 안내·spec 검증용.
        # 가정: input ≈ 3K tokens, output ≈ 1K tokens (실측 self-patterns·parent-patterns 평균).
        ESTIMATED_INPUT_TOKENS = 3_000
        ESTIMATED_OUTPUT_TOKENS = 1_000

        def self.estimated_cost_per_synth(model_id)
          meta = MODELS[model_id]
          return nil unless meta
          input_cost = ESTIMATED_INPUT_TOKENS * meta[:in_per_mtok] / 1_000_000.0
          output_cost = ESTIMATED_OUTPUT_TOKENS * meta[:out_per_mtok] / 1_000_000.0
          (input_cost + output_cost).round(4)
        end

        # allowlist 검증 — UI/ENV 에서 받은 model 문자열이 카탈로그에 있는지.
        def self.valid_model?(model_id)
          MODELS.key?(model_id)
        end

        def initialize(api_key: ENV.fetch("ANTHROPIC_API_KEY", nil),
          model: DEFAULT_MODEL,
          base_url: BASE_URL)
          @api_key = api_key
          @model = model
          @base_url = base_url
        end

        attr_reader :model

        def chat(system:, user:)
          raise "ANTHROPIC_API_KEY 환경 변수 필요" if @api_key.nil? || @api_key.empty?

          payload = build_payload(system, user)
          uri = URI(@base_url)
          req = Net::HTTP::Post.new(uri,
            "Content-Type" => "application/json",
            "x-api-key" => @api_key,
            "anthropic-version" => API_VERSION)
          req.body = JSON.generate(payload)

          res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
            http.request(req)
          end

          raise "Anthropic API 오류: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
          parsed = JSON.parse(res.body)
          parsed.dig("content", 0, "text").to_s
        end

        def build_payload(system, user)
          {
            model: @model,
            max_tokens: 2048,
            system: system,
            messages: [
              {role: "user", content: user}
            ]
          }
        end
      end
    end
  end
end
