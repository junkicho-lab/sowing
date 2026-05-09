# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Sowing
  module Eval
    module Backends
      # Anthropic Messages API 백엔드 (W13-T02).
      #
      # ENV: ANTHROPIC_API_KEY 필수. 모델 기본 claude-haiku-4 (저비용).
      # Net::HTTP 만 사용 (외부 gem 0).
      class Anthropic < Base
        DEFAULT_MODEL = "claude-haiku-4-20260114"
        BASE_URL = "https://api.anthropic.com/v1/messages"
        API_VERSION = "2023-06-01"

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
