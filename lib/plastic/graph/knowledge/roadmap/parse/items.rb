# frozen_string_literal: true

require_relative "entry"
require_relative "item_line"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The checklist items of the batches: each opens at a "- [" line and runs until a blank line or the next one.
          class Items
            attr_reader :list

            def initialize(problems)
              @problems = problems
              @list = []
              @entry = nil
              @position = nil
            end

            def start(text, number, position)
              flush
              @entry = Entry.new(text, number)
              @position = position
            end

            def continue(text) = @entry&.add(text)

            def flush
              return unless @entry

              read(@entry.text, @entry.number)
              @entry = nil
            end

            private

            def read(joined, number)
              line = ItemLine.new(joined, @position)
              problem = line.problem
              problem ? @problems.add(problem, number) : @list << line.item
            end
          end
        end
      end
    end
  end
end
