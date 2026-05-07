# frozen_string_literal: true

module Sowing
  module Domain
    module ValueObjects
      # 태그 집합. 옵시디언 frontmatter `tags:` 배열에 대응.
      # 정책: strip + downcase + uniq + sort. 빈 태그·공백 전용 태그 거부.
      class TagSet
        def initialize(tags = [])
          unless tags.is_a?(Array)
            raise ArgumentError, "TagSet 입력은 Array여야 합니다 (받은 타입: #{tags.class})"
          end

          @tags = tags.map { |t| normalize(t) }.uniq.sort.freeze
          freeze
        end

        def to_a
          @tags
        end

        def each(&block)
          @tags.each(&block)
        end

        def include?(tag)
          return false unless tag.is_a?(String)
          @tags.include?(tag.strip.downcase)
        end

        def size
          @tags.size
        end
        alias_method :length, :size

        def empty?
          @tags.empty?
        end

        def ==(other)
          other.is_a?(self.class) && to_a == other.to_a
        end
        alias_method :eql?, :==

        def hash
          [self.class, @tags].hash
        end

        def inspect
          "#<#{self.class.name} #{@tags.inspect}>"
        end

        private

        def normalize(tag)
          unless tag.is_a?(String)
            raise ArgumentError, "태그는 String이어야 합니다 (받은 타입: #{tag.class})"
          end

          stripped = tag.strip.downcase
          if stripped.empty?
            raise ArgumentError, "빈 태그는 허용되지 않습니다 (입력: #{tag.inspect})"
          end

          stripped
        end
      end
    end
  end
end
