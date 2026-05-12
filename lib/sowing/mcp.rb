# frozen_string_literal: true

module Sowing
  # MCP (Model Context Protocol) 서버 — 외부 에이전트가 Sowing 의 sensor·actuator 를
  # JSON-RPC 로 호출 (W9-T02).
  #
  # ADR-013 의 Phase 9 구현: agent-native surface. 사용자는 Claude Desktop / Codex /
  # ChatGPT 등 MCP 클라이언트에서 Sowing 을 직접 사용 가능.
  #
  # 진입점: `bin/sowing-mcp` — stdio transport.
  # 도구는 모두 결정적 (LLM 미사용). 본 Phase 는 sensor 만 (read-only). actuator
  # (write) 는 W9-T03 에서 audit_log + with_actor("agent") 로 추가.
  module MCP
    # 싱글턴 의존성. 테스트는 .repositories= 로 격리, 또는 .reset! 로 default 복귀.
    class << self
      def repositories
        @repositories ||= default_repositories
      end

      attr_writer :repositories

      def reset!
        @repositories = nil
      end

      private

      def default_repositories
        {
          vault: Repositories::VaultRepo.new(vault_dir: Core::Paths.vault_dir),
          index: Repositories::IndexRepo.new
        }
      end
    end
  end
end
