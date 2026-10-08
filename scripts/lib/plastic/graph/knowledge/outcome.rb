# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # Reads one intent's outcome.md: the bullets under its Verification
      # heading, of any level, up to the next heading of the same or a higher
      # level. A bullet reads without its dash, checkbox and bold marks. No
      # document means no bullets.
      class Outcome
        HEADING = /\A(#+)\s*(.*?)\s*\z/
        BULLET = /\A[-*]\s*(?:\[[ xX]\]\s*)?(.+)\z/

        def initialize(retrieval, intent_id)
          document = retrieval.documents(intent_id).find { |candidate| candidate.path == "outcome.md" }
          @lines = document ? document.body.lines.map(&:chomp) : []
        end

        def merged? = recorded?("Merged")

        def architecture_map? = recorded?("Architecture map")

        def verification = section.filter_map { |line| line[BULLET, 1]&.delete("*")&.strip }

        private

        def recorded?(label)
          verification.any? { |bullet| bullet.match?(/\A#{Regexp.escape(label)}\s*:\s*\S/i) }
        end

        def section
          start = @lines.index { |line| heading(line)&.last&.casecmp?("Verification") }
          return [] unless start

          depth = heading(@lines[start]).first
          @lines[(start + 1)..].take_while { |line| (heading(line)&.first || depth + 1) > depth }
        end

        def heading(line)
          found = line.match(HEADING)
          [found[1].size, found[2]] if found
        end
      end
    end
  end
end
