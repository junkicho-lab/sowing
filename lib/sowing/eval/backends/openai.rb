# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Sowing
  module Eval
    module Backends
      # OpenAI Chat Completions 백엔드 (W13-T02).
      #
      # ENV: OPENAI_API_KEY 필수. 모델은 기본 gpt-4o-mini.
      # Net::HTTP 만 사용 (외부 gem 0).
      #
      # 본 클래스는 unit test 에서 호출 안 함 — 실제 모델 호출은 사용자가 환경 변수
      # 세팅 후 rake eval:run 등에서. spec 은 #initialize 와 #build_payload 만 검증.
      class OpenAI < Base
        DEFAULT_MODEL = "gpt-4o-mini"
        BASE_URL = "https://api.openai.com/v1/chat/completions"

        def initialize(api_key: ENV.fetch("OPENAI_API_KEY", nil),
          model: DEFAULT_MODEL,
          base_url: BASE_URL)
          @api_key = api_key
          @model = model
          @base_url = base_url
        end

        attr_reader :model

        def chat(system:, user:)
          raise "OPENAI_API_KEY 환경 변수 필요" if @api_key.nil? || @api_key.empty?

          payload = build_payload(system, user)
          uri = URI(@base_url)
          req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json",
            "Authorization" => "Bearer #{@api_key}")
          req.body = JSON.generate(payload)

          res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
            http.request(req)
          end

          raise "OpenAI API 오류: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
          parsed = JSON.parse(res.body)
          parsed.dig("choices", 0, "message", "content").to_s
        end

        # 단위 테스트용 — payload 구조 검증.
        def build_payload(system, user)
          {
            model: @model,
            messages: [
              {role: "system", content: system},
              {role: "user", content: user}
            ],
            response_format: {type: "json_object"},
            temperature: 0
          }
        end
      end
    end
  end
end
