# frozen_string_literal: true

require "rack/utils"

module Sowing
  module Core
    module Markdown
      # 옵시디언 호환 위키링크 [[target]] / [[target|alias]] 처리.
      #
      # W3-T01 범위:
      #   - 표준 두 형식만 (target, target|display)
      #   - section "#section", block "^block-id" 표기는 W3+에서 확장
      #   - 코드블록 안의 [[...]]도 추출됨 (정규식 단순화 — 한계 명시).
      #     실사용에선 사용자가 의도한 위키링크와 코드 예시가 거의 충돌하지 않음.
      #
      # 변환 결과 a 태그:
      #   <a href="#" class="wiki-link" data-wiki-target="…">display</a>
      #   - W3-T02 그래프 인덱스 후 href를 실제 노트 경로로 해석할 예정.
      #   - 옵시디언 본 마크다운(.md)에는 [[…]] 형태 그대로 보존(round-trip).
      class WikiLink
        # 정규식:
        #   [[target]]  또는 [[target|display]]
        #   target: 줄바꿈·]·[·| 금지
        #   display: 줄바꿈·]·[ 금지 (| 는 OK… 두 번째 |부터는 display 일부)
        #   non-greedy로 인접한 [[…]] 분리
        WIKI_LINK_RE = /\[\[([^\[\]|\n]+?)(?:\|([^\[\]\n]+?))?\]\]/

        CSS_CLASS = "wiki-link"

        attr_reader :target, :display

        # @param target  [String] 링크가 가리키는 대상 (제목·경로)
        # @param display [String, nil] 표시 텍스트. nil이면 target과 동일.
        def initialize(target:, display: nil)
          unless target.is_a?(String) && !target.strip.empty?
            raise ArgumentError, "target은 비어있지 않은 String이어야 합니다 (받은: #{target.inspect})"
          end
          unless display.nil? || display.is_a?(String)
            raise ArgumentError, "display는 String이거나 nil이어야 합니다 (받은: #{display.class})"
          end

          @target = target.strip.freeze
          @display = (display.nil? || display.strip.empty?) ? @target : display.strip.freeze
          freeze
        end

        # 본문에서 모든 위키링크 추출.
        # @param text [String]
        # @return [Array<WikiLink>] 본문 등장 순서
        def self.extract(text)
          return [] unless text.is_a?(String)

          text.scan(WIKI_LINK_RE).filter_map do |raw_target, raw_display|
            target = raw_target.to_s.strip
            next nil if target.empty?
            new(target: target, display: raw_display)
          end
        end

        # 본문 내 [[…]] 모두를 <a class="wiki-link"> HTML로 치환한 새 String 반환.
        # 코드블록·인라인 코드 보호 없음 (W3-T01 한계).
        # @param text [String]
        # @return [String]
        def self.transform(text)
          return text.to_s unless text.is_a?(String)

          text.gsub(WIKI_LINK_RE) do
            target = ::Regexp.last_match(1).to_s.strip
            display = ::Regexp.last_match(2)
            if target.empty?
              ::Regexp.last_match(0) # 빈 target은 원본 그대로
            else
              render_html(target: target, display: display)
            end
          end
        end

        # 단일 위키링크 HTML 렌더 (escape 포함).
        # @return [String]
        def self.render_html(target:, display: nil)
          effective_display =
            if display.nil? || display.to_s.strip.empty?
              target
            else
              display.to_s.strip
            end

          esc_target = Rack::Utils.escape_html(target)
          esc_display = Rack::Utils.escape_html(effective_display)
          %(<a href="#" class="#{CSS_CLASS}" data-wiki-target="#{esc_target}">#{esc_display}</a>)
        end

        # 인스턴스 메서드로도 노출.
        def render_html
          self.class.render_html(target: target, display: display)
        end

        # 옵시디언 본 마크다운 round-trip (round-trip 호환성 spec에 사용).
        # @return [String] "[[target]]" 또는 "[[target|display]]"
        def to_markdown
          (display == target) ? "[[#{target}]]" : "[[#{target}|#{display}]]"
        end

        def ==(other)
          other.is_a?(self.class) && target == other.target && display == other.display
        end
        alias_method :eql?, :==

        def hash
          [self.class, target, display].hash
        end

        def inspect
          "#<#{self.class.name} target=#{target.inspect} display=#{display.inspect}>"
        end
      end
    end
  end
end
