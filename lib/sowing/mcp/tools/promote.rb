# frozen_string_literal: true

module Sowing
  module MCP
    module Tools
      # 메모/필기를 다음 단계로 승격 (메모→필기 또는 메모/필기→기록).
      # ID 유지 — backlinks·위키링크 그래프 보존 (W3-T06/T07 정책).
      # 옛 path 는 휴지통(`.sowing/trash`)으로 이동, 새 path 에 새 파일.
      class Promote < Base
        tool_name "promote"
        description "메모(memo)→필기(note) 또는 메모/필기→기록(record) 승격. ID 유지, 옛 파일은 휴지통."
        input_schema(
          properties: {
            id: {
              type: "string",
              description: "승격 대상 entry 의 ULID (필수)."
            },
            to: {
              type: "string",
              enum: %w[note record],
              description: "승격 목표 모드. note 또는 record."
            },
            title: {type: "string", description: "승격 후 제목 (필수)."},
            category: {
              type: "string",
              description: "카테고리. note 인 경우 lessons/trainings/books/meetings 중 하나, record 는 자유 텍스트."
            },
            source: {
              type: "string",
              description: "출처. to=note 인 경우만 필수, record 는 무시."
            },
            tags: {
              type: "array",
              items: {type: "string"},
              description: "태그 override (선택). nil이면 원본 entry tags 유지."
            }
          },
          required: %w[id to title category]
        )

        def self.call(id:, to:, title:, category:, source: nil, tags: nil, server_context: nil)
          target = to.to_s
          unless %w[note record].include?(target)
            return error_response("to 는 'note' 또는 'record' 여야 합니다 (받은 값: #{to.inspect})")
          end

          if target == "note" && (source.nil? || source.to_s.strip.empty?)
            return error_response("to=note 일 때 source 는 필수")
          end

          result = Core::AuditLog.with_actor("agent") do
            invoke_use_case(target: target, id: id, title: title,
              category: category, source: source, tags: tags)
          end

          if result.success?
            indexed = index_repo.find(result.value!.id)
            json_response(serialize_entry(indexed).merge(promoted_to: target))
          else
            error_response("Promote 실패: #{result.failure.inspect}")
          end
        end

        def self.invoke_use_case(target:, id:, title:, category:, source:, tags:)
          if target == "note"
            UseCases::PromoteToNote.new(vault_repo: vault_repo, index_repo: index_repo).call(
              id: id, title: title, category: category, source: source, tags: tags
            )
          else
            UseCases::PromoteToRecord.new(vault_repo: vault_repo, index_repo: index_repo).call(
              id: id, title: title, category: category, tags: tags
            )
          end
        end
      end
    end
  end
end
