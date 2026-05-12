# frozen_string_literal: true

module Sowing
  # Bounded Context #3 — Insight (통찰·합성).
  #
  # 책임: 17 합성기 + 자기 거울 5축. ADR-013 자율 mutation 0 —
  # 모든 합성 결과는 `.sowing/synth/` 검토 대기 폴더, 사용자 수락 클릭으로만
  # 정식 기록 이동.
  #
  # 도메인:
  #   - Insight::Synthesis — 합성 결과 1건 (Phase R Stage 4a R4a-T01)
  #   - Insight::SynthesisRepo — 파일 영속화 어댑터 (R4a-T02)
  #   - Insight::USE_CASE_DISPATCH — type → 옛 UseCases::Synthesize* 매핑
  #
  # accept (수락) 시 Knowledge::Record 로 이전 — knowledge 의존.
  # 의존: Core + Capture + Knowledge.
  module Insight
    # 18 합성기 type (17 + self-mirror, ADR-013 + Phase 13 W28-T01).
    SYNTHESIZER_TYPES = %w[
      students lessons reflections patterns contradictions
      consultations assessments trainings weekly orphans
      lesson-series tag-clusters seasonal parent-patterns
      self-patterns learning-progress event-causality self-mirror
    ].freeze

    # type → 옛 UseCases::* 클래스 매핑 (Strangler Fig 경유점).
    # 본 dispatch table 은 Stage 5 마이그레이션에서 use case 들이 Insight 네임스페이스로
    # 이동될 때 사라짐. 그 전까지는 Façade 가 옛 구현을 그대로 호출.
    USE_CASE_DISPATCH = {
      "students" => :SynthesizeStudentDigest,
      "lessons" => :ExtractLessonPatterns,
      "reflections" => :SynthesizeSemesterReflection,
      "patterns" => :ExtractLessonPatterns,
      "contradictions" => :DetectContradictions,
      "consultations" => :SynthesizeParentConsultation,
      "assessments" => :SynthesizeAssessmentTrend,
      "trainings" => :ExtractTrainingApplications,
      "weekly" => :SynthesizeWeeklyReview,
      "orphans" => :DetectOrphanEntries,
      "lesson-series" => :SynthesizeLessonSeries,
      "tag-clusters" => :SynthesizeTagClusters,
      "seasonal" => :SynthesizeSeasonalPattern,
      "parent-patterns" => :SynthesizeParentPatterns,
      "self-patterns" => :SynthesizeSelfPatterns,
      "learning-progress" => :SynthesizeLearningProgress,
      "event-causality" => :SynthesizeEventCausality,
      "self-mirror" => :SynthesizeSelfMirror
    }.freeze

    # type → 수락 시 Knowledge::Record 의 category 매핑 (옛 SynthController.SYNTH_TYPES).
    ACCEPT_CATEGORY = {
      "students" => "학생기록",
      "lessons" => "수업기록",
      "reflections" => "학기회고",
      "patterns" => "수업기록",
      "contradictions" => "학생기록",
      "consultations" => "상담",
      "assessments" => "평가기록",
      "trainings" => "연수기록",
      "weekly" => "주간회고",
      "orphans" => "메모정리",
      "lesson-series" => "수업기록",
      "tag-clusters" => "메모정리",
      "seasonal" => "학교운영",
      "parent-patterns" => "상담",
      "self-patterns" => "교사성장",
      "learning-progress" => "학생기록",
      "event-causality" => "교사성장",
      "self-mirror" => "교사성장"
    }.freeze

    # 합성 use case 가 Failure 를 반환할 때 raise.
    class GenerationFailed < StandardError
      attr_reader :type, :reason

      def initialize(type, reason)
        @type = type
        @reason = reason
        super("Synthesis 생성 실패 (#{type}): #{reason.inspect}")
      end
    end

    @repo_mutex = Mutex.new

    class << self
      # 단일 합성 생성 — type 에 맞는 옛 UseCases::Synthesize* 클래스에 위임.
      # 성공 시 SynthesisRepo 에서 결과 파일을 Synthesis 로 회수.
      # 실패 시 Insight::GenerationFailed (reason symbol 보존).
      # @param type [Symbol, String] SYNTHESIZER_TYPES 중 하나
      # @param params [Hash] type-specific kwargs (학생명·연도 등)
      # @return [Sowing::Insight::Synthesis]
      def generate(type:, **params)
        validate_type!(type)
        klass_name = USE_CASE_DISPATCH.fetch(type.to_s)
        use_case = UseCases.const_get(klass_name)

        result = use_case.new.call(**params)

        if result.respond_to?(:success?) && result.success?
          path = Pathname.new(result.value!.to_s)
          slug = File.basename(path, ".md")
          repo.find(type: type.to_sym, slug: slug) ||
            raise(GenerationFailed.new(type, :synthesis_file_missing))
        else
          reason = result.respond_to?(:failure) ? result.failure : :unknown_failure
          raise GenerationFailed.new(type, reason)
        end
      end

      # 대기 중인 모든 synthesis 수.
      # @return [Integer]
      def pending_count(type: nil)
        repo.count_pending(type: type)
      end

      # 대기 중 Synthesis 목록.
      # @param type [Symbol, nil] 특정 type 만 (nil = 전체 18 type)
      # @return [Array<Sowing::Insight::Synthesis>]
      def pending(type: nil)
        repo.pending(type: type)
      end

      # 단건 조회 — id ("type:slug" 형태).
      # @return [Sowing::Insight::Synthesis, nil]
      def find(id)
        type, slug = id.to_s.split(":", 2)
        return nil if type.nil? || slug.nil?
        repo.find(type: type.to_sym, slug: slug)
      end

      # 합성 수락 — Knowledge::Record 로 이전 + 원본 synth 파일 삭제.
      # @param id [String] "type:slug"
      # @return [Sowing::Knowledge::Record] 생성된 record
      # @raise [ArgumentError] synthesis 못 찾을 때
      def accept(id)
        synth = find(id)
        raise ArgumentError, "Synthesis 못 찾음: #{id}" if synth.nil?

        category = ACCEPT_CATEGORY.fetch(synth.type.to_s, "기록")
        record = Knowledge.create_record(
          title: synth.title,
          body: synth.body,
          category: category,
          promoted_from: synth.path&.to_s
        )

        # 수락 시 원본 synth 파일 삭제 (휴지통 아님 — 정식 Record 로 승격됨)
        synth_abs = repo.send(:type_dir, synth.type).join("#{File.basename(synth.path.to_s, ".md")}.md")
        synth_abs.delete if synth_abs.exist?

        record
      end

      # 합성 거절 — 휴지통 이동 (영구 삭제 0).
      # @return [Pathname, nil] 휴지통 위치
      def reject(id)
        type, slug = id.to_s.split(":", 2)
        return nil if type.nil? || slug.nil?
        repo.reject(type: type.to_sym, slug: slug)
      end

      # DI 진입점.
      def repo
        @repo_mutex.synchronize { @repo ||= SynthesisRepo.new }
      end

      attr_writer :repo

      def reset_repo!
        @repo_mutex.synchronize { @repo = nil }
      end

      private

      def validate_type!(type)
        return if SYNTHESIZER_TYPES.include?(type.to_s)
        raise ArgumentError,
          "type 는 SYNTHESIZER_TYPES 중 하나여야 합니다 (받은 값: #{type.inspect})"
      end
    end
  end
end
