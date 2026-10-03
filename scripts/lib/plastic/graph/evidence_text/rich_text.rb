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
          output = String.new
          cursor = 0
          while (first = escape_at(source, cursor))
            output << source[cursor...first.begin(0)]
            second = escape_at(source, first.end(0))
            output << (adjacent_pair(first, second) || first[0])
            cursor = adjacent_pair(first, second) ? second.end(0) : first.end(0)
          end
          output << source[cursor..]
        end

        def escape_at(source, offset) = /\\u(-?\d+)\?/.match(source, offset)

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
