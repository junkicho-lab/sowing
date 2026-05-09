# frozen_string_literal: true

require "mcp"

module Sowing
  module MCP
    # 공식 ::MCP::Server 래퍼. 도구를 등록하고 stdio transport 진입점 제공.
    # MCP 모듈 자체의 .repositories DI 싱글턴은 lib/sowing/mcp.rb 에 정의.
    class Server
      TOOLS = [
        # Read-only sensors (W9-T02)
        Tools::ListMemos,
        Tools::Search,
        Tools::ReadEntry,
        Tools::Health,
        # Write actuators (W9-T03) — audit log actor=agent 로 자동 기록
        Tools::CreateMemo,
        Tools::CreateNote,
        Tools::CreateRecord,
        Tools::Promote
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

          Sensors (read-only):
            - list_memos: 모드별 entry 목록 (페이지네이션 지원)
            - search: 한국어 자동 라우팅 검색 (FTS5 + LIKE 폴백)
            - read_entry: 단일 entry frontmatter + body
            - health: 시스템 상태 + 카운트

          Actuators (write — audit log actor=agent 자동 기록):
            - create_memo: 빠른 메모 생성
            - create_note: 카테고리 4종(lessons/trainings/books/meetings) + source 필수
            - create_record: 자유 카테고리, 30_Records/{YYYY}/{cat}/ 저장
            - promote: 메모→필기 또는 메모/필기→기록 (ID 유지, 옛 파일은 휴지통)

          모든 mutation 은 .sowing/audit.log 에 JSON Lines 로 기록됩니다.
          ADR-013: LLM 추론은 외부 에이전트가 담당. 본 서버 도구는 모두 결정적 코드.
        TEXT
      end
    end
  end
end
