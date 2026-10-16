# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Reads bullets within Decisions headings, including nested sections.
        class DecisionBullets
          def self.call(text) = new.read(text)

          def read(text)
            @level = nil
            text.each_line.filter_map { |line| bullet(line.chomp) }
          end

          private

          def bullet(line)
            heading = line.match(/\A(#+)\s+(.+)\z/)
            return section(heading) if heading

            line.strip.delete_prefix("- ").strip if @level && line.strip.start_with?("- ")
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
