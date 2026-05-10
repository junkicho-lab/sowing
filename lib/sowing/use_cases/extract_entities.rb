# frozen_string_literal: true

require "dry/monads"
require "json"
require "time"

module Sowing
  module UseCases
    # entry 본문에서 학생·과목·위치 추출 → entities + entity_mentions 갱신 (W17-T01).
    #
    # ADR-013 의 Phase 2 거부 5종 준수:
    #   - 결정적 fallback 항상 존재 (LLM 미사용 모드 1급)
    #   - LLM 호출은 옵트인 (backend 주입 시에만)
    #   - audit log 통합 — LLM 사용 시 actor=agent 자동 마킹 (Persistence 와 동일 패턴)
    #
    # 두 모드:
    #   1. 결정적: 한국어 학생 인명 정규식 + 과목/위치 사전 매칭. CI/오프라인 안전.
    #   2. LLM: backend.chat 호출 → JSON 파싱. 실패 시 결정적으로 graceful fallback.
    #
    # entities 는 멱등 — 같은 entry 를 두 번 호출해도 mention_count 만 증가, 새 row 생성 안 함.
    class ExtractEntities
      include Dry::Monads[:result]

      # 한국어 학생 인명 화이트리스트 — 결정적 모드는 사전 매칭만.
      # 한국어 NER 없이 본문에서 인명 vs 일반 명사 구분 불가. False positive 회피 위해
      # 알려진 한국 인명만 인식. 새 이름은 LLM 모드(옵트인)에서만 잡힘.
      # 본 리스트는 generate_corpus.rb 의 NAMES 와 동일 + 시드 이름 추가.
      KNOWN_STUDENT_NAMES = %w[
        민준 서연 지호 윤아 도현 나래 서윤 시우 하준 예린 채원 우진 다은 시원 건우 가온
        지우 서하 하윤 도윤 이안 지안 시아 라윤 주안 이준 예준 서준 하원 시연 지유
      ].freeze

      # 결정적 모드에서 인명을 본문에서 인식할 때의 조사 패턴 (인명 이후).
      # 받침 있는 이름 + "이" + 조사 또는 받침 없는 이름 + 조사 직접.
      PARTICLE_AFTER_NAME = /(?:이[가는를의와도에]|이[\s.,!?]|[가는을를의와과도에][\s.,!?])/

      # 한국 K-12 과목 사전.
      SUBJECTS = %w[국어 수학 사회 과학 영어 도덕 음악 미술 체육 실과 정보 한문 한국사 통합교과 창체].freeze

      # 학교 주요 장소.
      LOCATIONS = %w[교실 도서관 운동장 강당 음악실 미술실 컴퓨터실 과학실 체육관 보건실 식당 회의실 상담실].freeze

      def initialize(db: nil, llm_backend: nil, clock: Time)
        @db = db || Infrastructure::DB.connection
        @llm_backend = llm_backend
        @clock = clock
      end

      # @param entry_id [String] entries.id (ULID 문자열)
      # @param body [String] 본문 (frontmatter 제외)
      # @return [Result] Success({"students"=>[...], "subjects"=>[...], "locations"=>[...]})
      def call(entry_id:, body:)
        entities = if @llm_backend
          Infrastructure::AuditLog.with_actor("agent") { extract_via_llm(body) }
        else
          extract_deterministic(body)
        end

        sync_entities(entry_id, entities)
        Success(entities)
      end

      private

      def extract_deterministic(body)
        # 화이트리스트 인명 + 조사 동반 매칭만 students 로 간주 (false positive 회피).
        students = KNOWN_STUDENT_NAMES.select do |name|
          # 단어 경계 + 인명 + 조사 패턴.
          re = /(?<=^|[\s.,!?])#{Regexp.escape(name)}#{PARTICLE_AFTER_NAME.source}/
          body.match?(re)
        end
        subjects = SUBJECTS.select { |s| body.include?(s) }
        locations = LOCATIONS.select { |l| body.include?(l) }

        {"students" => students, "subjects" => subjects, "locations" => locations}
      end

      def extract_via_llm(body)
        response = @llm_backend.chat(
          system: llm_system_prompt,
          user: body
        )
        parsed = JSON.parse(response)
        # 결과 정규화 — 누락된 키 보강, 배열 아닌 값 거부.
        {
          "students" => Array(parsed["students"] || []).map(&:to_s),
          "subjects" => Array(parsed["subjects"] || []).map(&:to_s),
          "locations" => Array(parsed["locations"] || []).map(&:to_s)
        }
      rescue JSON::ParserError, TypeError
        # 응답 파싱 실패 → 결정적 fallback.
        extract_deterministic(body)
      end

      def llm_system_prompt
        <<~TXT
          한국어 교사 일지에서 학생 이름·과목·위치를 추출하라.
          출력은 JSON 객체 하나, 키는 students/subjects/locations 만.
          값은 문자열 배열. 추측 금지 — 본문에 명시된 것만.
          예: {"students":["민준","서연"],"subjects":["수학"],"locations":["교실"]}
        TXT
      end

      def sync_entities(entry_id, entities)
        @db.transaction do
          now = @clock.now.iso8601
          entities.each do |type_plural, names|
            type = type_plural.to_s.delete_suffix("s") # students → student
            Array(names).each do |name|
              next if name.to_s.strip.empty?
              entity_id = upsert_entity(type, name, now)
              # 같은 entry 에서 같은 entity 중복 mention 방지 (single mention per entry).
              existing_mention = @db[:entity_mentions]
                .where(entity_id: entity_id, entry_id: entry_id).first
              @db[:entity_mentions].insert(entity_id: entity_id, entry_id: entry_id) unless existing_mention
            end
          end
        end
      end

      def upsert_entity(type, name, now)
        row = @db[:entities].where(type: type, name: name).first
        if row
          @db[:entities].where(id: row[:id]).update(
            last_seen_at: now,
            mention_count: row[:mention_count] + 1
          )
          row[:id]
        else
          @db[:entities].insert(
            type: type,
            name: name,
            first_seen_at: now,
            last_seen_at: now,
            mention_count: 1
          )
        end
      end
    end
  end
end
