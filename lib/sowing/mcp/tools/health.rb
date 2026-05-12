# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 시스템 상태·통계 요약. 외부 에이전트가 "Sowing 통계 요약해줘" 시 호출.
      # bin/sowing-doctor 의 핵심 정보를 머신 가독 JSON 으로.
      class Health < Base
        tool_name "health"
        description "Sowing 시스템 상태 + 모드별 entry 카운트 + 볼트 경로 + 최근 audit 활동."
        input_schema(properties: {})

        def self.call(server_context: nil)
          mode_counts = %i[memo note record].to_h { |m| [m, index_repo.count(mode: m)] }

          payload = {
            version: Sowing::VERSION,
            env: Sowing.env,
            vault_dir: vault_repo.vault_dir.to_s,
            entry_counts: mode_counts.transform_keys(&:to_s),
            total_entries: mode_counts.values.sum,
            audit_log_present: Core::AuditLog.instance.path.exist?,
            recent_audit_count: recent_audit_count
          }

          json_response(payload)
        end

        def self.recent_audit_count
          Core::AuditLog.instance.read_all.size
        rescue
          0
        end
      end
    end
  end
end
