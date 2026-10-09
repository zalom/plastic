# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Intent
        # The Notes section of an intent outcome.
        class Notes
          HEADING = "## Notes"
          KINDS = %w[Review Commit Report].freeze
          STARTER = "# Outcome"

          def self.for(body)
            lines = body.to_s.lines.map(&:chomp)
            new(lines.empty? ? [STARTER] : lines)
          end

          def initialize(lines)
            @lines = lines
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
