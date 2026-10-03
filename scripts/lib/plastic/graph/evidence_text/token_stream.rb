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
          fragments = Fragments.new(@source)
          scan(fragments) { |match| yield(match) }
          NormalizedText.new(fragments.values).build
        end

        private

        def scan(fragments)
          fragments.append_tail(matches(fragments) { |match| yield(match) })
        end

        def matches(fragments)
          cursor = 0
          while (match = @pattern.match(@source, cursor))
            cursor = fragments.append_match(cursor, match) { |found| yield(found) }
          end
          cursor
        end

        # Owns fragment assembly and the source-line accounting for one stream.
        class Fragments
          attr_reader :values

          def initialize(source)
            @source = source
            @values = []
          end

          def append_match(cursor, match)
            start = match.begin(0)
            append(@source[cursor...start], line_at(cursor))
            append(yield(match), line_at(start))
            match.end(0)
          end

          def append_tail(cursor) = append(@source[cursor..], line_at(cursor))

          private

          def append(value, line)
            value.each_char do |character|
              @values << [character, line]
              line += 1 if character == "\n"
            end
          end

          def line_at(offset) = @source[0...offset].count("\n") + 1
        end
      end
    end
  end
end
