# frozen_string_literal: true

require "mcp"

module Sowing
  module MCP
    # 공식 ::MCP::Server 래퍼. 도구를 등록하고 stdio transport 진입점 제공.
    # MCP 모듈 자체의 .repositories DI 싱글턴은 lib/sowing/mcp.rb 에 정의.
    class Server
      TOOLS = [
        Tools::ListMemos,
        Tools::Search,
        Tools::ReadEntry,
        Tools::Health
      ].freeze

      def initialize(name: "sowing", version: Sowing::VERSION)
        @server = ::MCP::Server.new(
          name: name,
          version: version,
          instructions: instructions,
          tools: TOOLS
        )
      end

      attr_reader :server

      # stdio 모드 진입 — bin/sowing-mcp 에서 호출. blocking.
      def open_stdio
        transport = ::MCP::Server::Transports::StdioTransport.new(@server)
        transport.open
      end

      private

      def instructions
        <<~TEXT
          Sowing 은 한국 교사를 위한 로컬 우선 마크다운 노트 앱입니다.
          데이터 모델: 메모(memo) → 필기(note) → 기록(record) 3단계.
          본 MCP 서버는 read-only sensor 도구를 제공합니다 (Phase 9-T02).
          쓰기 actuator 는 후속 단계에서 추가됩니다 (W9-T03).
        TEXT
      end
    end
  end
end
