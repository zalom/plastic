# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        module Text
          # The character offset where each source line of a text starts, and the
          # first and last line of any slice of that text.
          class SourceLines
            # The first and last line a slice of the text touches.
            Slice = Data.define(:first, :last)

            EMPTY = Slice.new(nil, nil)

            attr_reader :line_starts

            def self.for(source) = new(starts(source), source.length)

            def self.starts(source)
              return [] if source.empty?

              [0, *source.each_char.with_index(1).filter_map { |character, position| position if character == "\n" && position < source.length }]
            end

            def initialize(line_starts, length)
              @line_starts = line_starts
              @length = length
            end

            def slice(start, length)
              return if start > @length
              return EMPTY if start == @length || length < 1

              Slice.new(line_at(start), line_at([start + length, @length].min - 1))
            end

            private

            def line_at(offset) = @line_starts.bsearch_index { |first| first > offset } || @line_starts.length
          end
        end
      end
    end
  end
end
