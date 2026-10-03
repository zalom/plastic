# frozen_string_literal: true

module Plastic
  module Graph
    module EvidenceText
      # Emits source fragments with their original line numbers, then normalizes them.
      class TokenStream
        def initialize(source, pattern)
          @source = source
          @pattern = pattern
        end

        def extract
          fragments = []
          cursor = append_matches(fragments) { |match| yield(match) }
          append(fragments, @source[cursor..], line_at(cursor))
          NormalizedText.new(fragments).build
        end

        private

        def append_matches(fragments)
          cursor = 0
          @source.to_enum(:scan, @pattern).each do
            match = Regexp.last_match
            cursor = append_match(fragments, cursor, match) { |found| yield(found) }
          end
          cursor
        end

        def append_match(fragments, cursor, match)
          start = match.begin(0)
          append(fragments, @source[cursor...start], line_at(cursor))
          append(fragments, yield(match), line_at(start))
          match.end(0)
        end

        def append(fragments, value, line)
          value.each_char do |character|
            fragments << [character, line]
            line += 1 if character == "\n"
          end
        end

        def line_at(offset) = @source[0...offset].count("\n") + 1
      end
    end
  end
end
