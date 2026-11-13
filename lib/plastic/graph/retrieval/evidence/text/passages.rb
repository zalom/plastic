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
            STEP = SIZE - OVERLAP

            class << self
              def build(source)
                extraction = source.is_a?(Extraction) ? source : Extraction.new(source, SourceLines.for(source))
                steps = extraction.body.scan(/.{1,#{STEP}}/m)
                steps.each_index.map { |index| passage(extraction, steps, index) }
              end

              private

              def passage(extraction, steps, index)
                body = steps[index] + steps.fetch(index + 1, "")[0, OVERLAP]
                lines = extraction.lines.slice(index * STEP, body.length)
                { body:, position: index + 1, line_start: lines.first, line_end: lines.last }
              end
            end
          end
        end
      end
    end
  end
end
