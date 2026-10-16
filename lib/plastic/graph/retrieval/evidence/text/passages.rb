# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        module Text
          # Splits extracted evidence into overlapping, source-addressable passages.
          class Passages
            SIZE = 1600
            OVERLAP = 200

            class << self
              def build(source)
                extraction = source.is_a?(Extraction) ? source : Extraction.new(source, SourceLines.for(source))
                offsets(extraction.body.length).each_with_index.map { |offset, index| passage(extraction, offset, index) }
              end

              private

              def offsets(length) = (0...length).step(SIZE - OVERLAP)

              def passage(extraction, offset, index)
                body = extraction.body[offset, SIZE]
                lines = extraction.lines.slice(offset, body.length)
                { body:, position: index + 1, line_start: lines.first, line_end: lines.last }
              end
            end
          end
        end
      end
    end
  end
end
