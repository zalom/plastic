# frozen_string_literal: true

module Plastic
  module Graph
    module EvidenceText
      # Decodes RTF control words, signed BMP values, and surrogate pairs.
      module RichText
        PATTERN = /\\u(-?\d+)\?|\\'([0-9a-f]{2})|\\[a-z]+-?\d* ?|[{}]/i

        module_function

        def extract(source)
          rendered = resolve_pairs(source)
          TokenStream.new(rendered, PATTERN).extract { |match| token(match) }
        end

        def token(match)
          unicode, hex = match.captures
          return codepoint(unicode).chr(Encoding::UTF_8) if unicode
          return hex.to_i(16).chr(Encoding::ISO_8859_1).encode(Encoding::UTF_8) if hex

          ""
        end

        def resolve_pairs(source)
          PairCursor.new(source).resolved
        end

        # Advances through RTF Unicode escapes while preserving unmatched escapes.
        class PairCursor
          def initialize(source)
            @source = source
            @output = String.new
            @cursor = 0
          end

          def resolved
            while (first = first_escape)
              advance(first)
            end
            @output << @source[@cursor..]
          end

          private

          def advance(first)
            append_prefix(first)
            append_escape(first)
          end

          def append_prefix(first) = @output << @source[@cursor...first.begin(0)]

          def append_escape(first)
            pair, ending = pair_result(first)
            @output << (pair || first[0])
            @cursor = ending
          end

          def pair_result(first)
            ending = first.end(0)
            second = escape_at(ending)
            pair = RichText.adjacent_pair(first, second)
            [pair, pair ? second.end(0) : ending]
          end

          def first_escape = escape_at(@cursor)
          def escape_at(offset) = /\\u(-?\d+)\?/.match(@source, offset)
        end

        def adjacent_pair(first, second)
          return unless second&.begin(0) == first.end(0)

          high, low = [first[1], second[1]].map { |value| codepoint(value) }
          return unless high.between?(0xD800, 0xDBFF) && low.between?(0xDC00, 0xDFFF)

          (0x10000 + ((high - 0xD800) << 10) + low - 0xDC00).chr(Encoding::UTF_8)
        end

        def codepoint(value)
          number = value.to_i
          number.negative? ? number + 65_536 : number
        end
      end
    end
  end
end
