# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Sowing
  module Eval
    module Backends
      # Ollama 로컬 백엔드 (W13-T02).
      #
      # 로컬 LLM 우선 — 데이터 외부 전송 0. ADR-013 의 "클라우드 LLM 강제 안 함" 원칙
      # 직접 구현. http://localhost:11434 기본.
      #
      # 모델: llama3.2 / qwen2.5 / gemma2 등 사용자가 ollama pull 한 것.
      class Ollama < Base
        DEFAULT_MODEL = "llama3.2"
        DEFAULT_BASE_URL = "http://localhost:11434/api/chat"

        def initialize(model: DEFAULT_MODEL,
          base_url: ENV.fetch("OLLAMA_URL", DEFAULT_BASE_URL))
          @model = model
          @base_url = base_url
        end

        attr_reader :model

        def chat(system:, user:)
          payload = build_payload(system, user)
          uri = URI(@base_url)
          req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
          req.body = JSON.generate(payload)

          res = Net::HTTP.start(uri.host, uri.port, read_timeout: 120) do |http|
            http.request(req)
          end

          raise "Ollama 오류: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
          parsed = JSON.parse(res.body)
          parsed.dig("message", "content").to_s
        end

        def build_payload(system, user)
          {
            model: @model,
            messages: [
              {role: "system", content: system},
              {role: "user", content: user}
            ],
            format: "json",
            stream: false,
            options: {temperature: 0}
          }
        end
      end
    end
  end
end
