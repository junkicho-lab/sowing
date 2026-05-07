# frozen_string_literal: true

require "ulid"

module Sowing
  module Domain
    module ValueObjects
      # ULID — Universally Unique Lexicographically Sortable Identifier.
      # 시간 기반 정렬 가능한 26자 식별자. Crockford Base32 (I/L/O/U 제외).
      class Ulid
        include Comparable

        FORMAT = /\A[0-9A-HJKMNP-TV-Z]{26}\z/

        attr_reader :value

        def self.generate
          new(::ULID.generate)
        end

        def self.parse(string)
          new(string)
        end

        def initialize(value)
          unless value.is_a?(String)
            raise ArgumentError, "ULID는 String이어야 합니다 (받은 타입: #{value.class})"
          end

          normalized = value.upcase
          unless FORMAT.match?(normalized)
            raise ArgumentError, "유효하지 않은 ULID 형식: #{value.inspect}"
          end

          @value = normalized.freeze
          freeze
        end

        def to_s
          @value
        end

        def inspect
          "#<#{self.class.name} #{@value}>"
        end

        def <=>(other)
          return nil unless other.is_a?(self.class)
          @value <=> other.value
        end

        def eql?(other)
          other.is_a?(self.class) && @value == other.value
        end

        def hash
          [self.class, @value].hash
        end
      end
    end
  end
end
