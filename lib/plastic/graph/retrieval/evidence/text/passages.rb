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
                following = steps.drop(1)
                steps.each_with_index.map { |step, index| passage(extraction, step + following.fetch(index, "")[0, OVERLAP], index) }
              end

              private

              def passage(extraction, body, index)
                lines = extraction.lines.slice(index * STEP, body.length)
                { body:, position: index.succ, line_start: lines.first, line_end: lines.last }
              end
            end
          end
        end
      end
    end
  end
end
