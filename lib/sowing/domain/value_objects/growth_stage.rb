# frozen_string_literal: true

module Sowing
  module Domain
    module ValueObjects
      # 씨앗-숲 시각화 단계 (W6-T03).
      #
      # 누적 entry 수에 따라 5단계 — 사용자가 "심고 가꾸는" 은유로 동기 부여.
      # 임계값은 메모 작성 부담을 고려해 점진적 (0 → 1 → 10 → 50 → 150).
      #
      # 단계가 도메인 값인 이유: SVG 렌더는 view 책임이지만 임계값 결정은
      # 비즈니스 로직 (격려 메시지·다음 목표 안내).
      class GrowthStage
        STAGES = [
          {key: :empty, threshold: 0, label: "🌱 시작 전",
           message: "첫 메모를 남겨 작은 씨앗을 심어 보세요."},
          {key: :seed, threshold: 1, label: "🌱 씨앗",
           message: "기록의 씨앗을 심으셨네요. 매일 한 줄씩 물을 주세요."},
          {key: :sprout, threshold: 10, label: "🌿 새싹",
           message: "기록이 새싹처럼 자라고 있습니다."},
          {key: :tree, threshold: 50, label: "🌳 나무",
           message: "한 그루의 나무가 되었습니다. 이제 그늘을 만들어요."},
          {key: :forest, threshold: 150, label: "🌲 숲",
           message: "기록의 숲이 우거졌습니다. 풍성한 자산이에요."}
        ].freeze

        attr_reader :total, :key, :label, :message, :next_threshold

        # @param total [Integer] 누적 entry 수
        def initialize(total)
          raise ArgumentError, "total은 0 이상" if total.negative?
          @total = total
          stage = STAGES.reverse.find { |s| total >= s[:threshold] } || STAGES.first
          @key = stage[:key]
          @label = stage[:label]
          @message = stage[:message]
          next_stage = STAGES.find { |s| s[:threshold] > total }
          @next_threshold = next_stage&.dig(:threshold)
        end

        def remaining_to_next
          return nil if @next_threshold.nil?
          @next_threshold - @total
        end

        def progress_ratio
          return 1.0 if @next_threshold.nil?
          current_min = STAGES.reverse.find { |s| @total >= s[:threshold] }[:threshold]
          span = @next_threshold - current_min
          return 0.0 if span <= 0
          ((@total - current_min).to_f / span).clamp(0.0, 1.0)
        end
      end
    end
  end
end
