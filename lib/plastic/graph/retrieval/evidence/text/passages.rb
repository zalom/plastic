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
                bodies(extraction.body).each_with_index.map { |body, index| passage(extraction, body, index) }
              end

              private

              def bodies(text)
                steps = text.scan(/.{1,#{STEP}}/m)
                steps.zip(steps.drop(1)).map { |step, following| step + following.to_s[0, OVERLAP] }
              end

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
