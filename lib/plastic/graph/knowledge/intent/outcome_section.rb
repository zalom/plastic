# frozen_string_literal: true

require_relative "../intent"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # One section of an intent outcome, under its heading. The section is found by its name at any heading level and
        # in any case, and ends at the next heading of the same or a higher level. A line added goes last in the section,
        # and a missing section is added at the end of the outcome under `heading` as given.
        class OutcomeSection
          STARTER = "# Outcome"
          HEADING = /\A(#+)\s*(.*?)\s*\z/

          def self.for(body, heading)
            lines = body.to_s.lines.map(&:chomp)
            new(lines.empty? ? [STARTER] : lines, heading)
          end

          def initialize(lines, heading)
            @lines = lines
            @heading = heading
            @name = heading[HEADING, 2]
          end

          # The whole outcome with `line` added to the section.
          def add(line)
            start = @lines.index { |text| text[HEADING, 2]&.casecmp?(@name) }
            start ? insert(start, line) : append(line)
            "#{@lines.join("\n")}\n"
          end

          # The whole outcome with each of `gone` taken out of the section, and the heading with them when the section is
          # left with no text. A missing section leaves the outcome as it is.
          def without(gone)
            start = @lines.index { |text| text[HEADING, 2]&.casecmp?(@name) }
            start && cut(start, section_end(start), gone)
            @lines.pop while @lines.last&.empty?
            "#{@lines.join("\n")}\n"
          end

          private

          def cut(start, stop, gone)
            kept = @lines[(start + 1)..stop].reject { |text| gone.include?(text) }
            @lines[start..stop] = kept.all?(&:empty?) ? [] : [@lines[start], *kept]
          end

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
            depth = @lines[start][HEADING, 1].size
            following = @lines[(start + 1)..].index { |text| (text[HEADING, 1]&.size || depth + 1) <= depth }
            following ? start + following : @lines.size - 1
          end
        end
      end
    end
  end
end
