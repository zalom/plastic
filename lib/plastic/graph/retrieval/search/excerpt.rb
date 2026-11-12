# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Search
        # Produces a bounded source-text excerpt around a literal search match.
        class Excerpt
          LIMIT = 320
          HALF_LIMIT = LIMIT / 2

          def initialize(terms)
            @terms = terms.scan(/[\p{Alnum}_]+/)
            @combining_marks = /\p{Mn}/
          end

          def call(body)
            body[excerpt_start(body), LIMIT]
          end

          private

          attr_reader :terms

          def excerpt_start(body)
            [source_index(body) - HALF_LIMIT, 0].max
          end

          def source_index(body)
            normalized, positions = normalized_positions(body)
            matched_index = terms.filter_map { |term| normalized.index(normalize(term)) }.min || 0
            positions.fetch(matched_index, 0)
          end

          def normalized_positions(text)
            text.each_char.with_index.each_with_object([+"", []]) do |(character, index), (normalized, positions)|
              fragment = normalize(character)
              normalized << fragment
              positions.concat([index] * fragment.length)
            end
          end

          def normalize(text) = text.unicode_normalize(:nfkd).gsub(@combining_marks, "").downcase
        end
      end
    end
  end
end
