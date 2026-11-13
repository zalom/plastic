# frozen_string_literal: true

require_relative "items"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The "## Batches" or "## Waves" section: the batch headings and the items under them.
          class Batches
            HEADING = /\A###\s+(?:Batch|Wave)\s+(\d+)\s*(?:[—-]\s*(.*))?\z/

            attr_reader :list

            def initialize(problems)
              @list = []
              @position = nil
              @items = Items.new(problems)
            end

            def items = @items.list

            def line(text, number)
              heading = HEADING.match(text)
              heading ? start(heading) : item_line(text.strip, number)
            end

            def finish = @items.flush

            private

            def start(heading)
              @items.flush
              @position = heading[1].to_i
              @list << Batch.new(position: @position, title: heading[2].to_s.strip)
            end

            def item_line(stripped, number)
              return @items.flush if stripped.empty?
              return @items.start(stripped, number, @position) if stripped.start_with?("- [")

              @items.continue(stripped)
            end
          end
        end
      end
    end
  end
end
