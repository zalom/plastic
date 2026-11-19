# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Intent
        # One section of an intent outcome, under its `## ` heading. A line added goes last in the section, and a missing
        # section is added at the end of the outcome.
        class OutcomeSection
          STARTER = "# Outcome"

          def self.for(body, heading)
            lines = body.to_s.lines.map(&:chomp)
            new(lines.empty? ? [STARTER] : lines, heading)
          end

          def initialize(lines, heading)
            @lines = lines
            @heading = heading
          end

          # The whole outcome with `line` added to the section.
          def add(line)
            start = @lines.index(@heading)
            start ? insert(start, line) : append(line)
            "#{@lines.join("\n")}\n"
          end

          private

          def append(line)
            @lines.pop while @lines.last&.empty?
            @lines.push("", @heading, "", line)
          end

          def insert(start, line)
            last = last_line_of_section(start)
            @lines.insert(last + 1, *[("" if last == start), line].compact)
          end

          def last_line_of_section(start)
            stop = section_end(start)
            stop -= 1 while stop > start && @lines[stop].empty?
            stop
          end

          def section_end(start)
            following = @lines[(start + 1)..].index { |text| text.start_with?("## ") }
            following ? start + following : @lines.size - 1
          end
        end
      end
    end
  end
end
