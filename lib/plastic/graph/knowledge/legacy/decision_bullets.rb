# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Reads bullets within Decisions headings, including nested sections.
        class DecisionBullets
          HEADING = /\A(#+)\s+(.+)\z/
          ITEM = /\A\s*- \s*(.*\S)\s*\z/

          def self.call(text) = new.read(text)

          def initialize
            @level = nil
          end

          def read(text)
            @level = nil
            text.each_line.filter_map { |line| bullet(line.chomp) }
          end

          private

          def bullet(line)
            heading = line.match(HEADING)
            return section(heading) if heading

            line[ITEM, 1] if @level
          end

          def section(heading)
            depth = heading[1].length
            @level = nil if @level && depth <= @level
            @level = depth if heading[2].strip == "Decisions"
            nil
          end
        end
      end
    end
  end
end
