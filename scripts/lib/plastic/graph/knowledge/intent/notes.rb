# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Intent
        # The text of an outcome with one more line under its `## Notes` heading.
        # The heading is added at the end when the outcome has none.
        class Notes
          HEADING = "## Notes"
          KINDS = %w[Review Commit Report].freeze
          STARTER = "# Outcome"

          def initialize(body)
            @lines = body.to_s.empty? ? [STARTER] : body.lines.map(&:chomp)
          end

          def add(kind, text)
            line = "- #{kind}: #{text}"
            start = @lines.index(HEADING)
            start ? insert(start, line) : append(line)
            "#{@lines.join("\n")}\n"
          end

          private

          def append(line)
            @lines.pop while @lines.last&.empty?
            @lines.push("", HEADING, "", line)
          end

          def insert(start, line)
            last = last_line_of_section(start)
            @lines.insert(last + 1, *[("" if last == start), line].compact)
          end

          def last_line_of_section(start)
            following = @lines[(start + 1)..].index { |text| text.start_with?("## ") }
            last = following ? start + following : @lines.size - 1
            last -= 1 while last > start && @lines[last].empty?
            last
          end
        end
      end
    end
  end
end
