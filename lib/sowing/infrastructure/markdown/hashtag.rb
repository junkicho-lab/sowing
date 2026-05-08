# frozen_string_literal: true

module Sowing
  module Infrastructure
    module Markdown
      # 옵시디언 호환 본문 #태그 추출.
      #
      # 인식 규칙 (옵시디언 표준):
      #   - "#" 직후 letter/digit/_/-/`/` 1개 이상
      #   - "#" 앞은 letter/digit/_가 아니어야 함 (예: "ab#cd"는 태그 아님)
      #   - digit-only는 태그 아님 (#123 → 거부, #1학년 → 인정)
      #
      # 한계 (W3-T05 단순화):
      #   - 코드블록 안의 #도 추출됨 (단순 정규식 — WikiLink와 동일 한계)
      #   - 슬래시 계층(`#parent/child`)은 그대로 추출, IndexRepo가 통째 태그로 저장
      module Hashtag
        HASHTAG_RE = /(?<![\p{L}\p{N}_])#([\p{L}\p{N}_\/-]+)/

        module_function

        # 본문에서 모든 #태그 추출 (등장 순서, 중복 제거).
        # @param text [String]
        # @return [Array<String>] # 빠진 순수 태그 이름들 (정규화 안 됨 — caller가 strip/downcase)
        def extract(text)
          return [] unless text.is_a?(String)

          text.scan(HASHTAG_RE).flatten
            .reject { |t| t.match?(/\A\d+\z/) } # digit-only 거부
            .uniq
        end
      end
    end
  end
end
