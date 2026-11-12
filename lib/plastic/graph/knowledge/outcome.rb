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
          @headings = @lines.map { |line| line.match(HEADING) }
        end

        # The messages that ask for the records this outcome lacks.
        def missing_records
          [("Add a line starting Merged: to the Verification section of outcome.md and run plastic sync up." unless merged?),
            ("Add a line starting Architecture map: to the Verification section of outcome.md and run plastic sync up." unless architecture_map?)].compact
        end

        def merged? = recorded?("Merged")

        def architecture_map? = recorded?("Architecture map")

        def pull_request? = recorded?("Pull request")

        def approved? = recorded?("Approved")

        def reverted? = recorded?("Reverted")

        def verification = section.filter_map { |line| line[BULLET, 1]&.delete("*")&.strip }

        private

        def recorded?(label)
          verification.any? { |bullet| bullet.match?(/\A#{Regexp.escape(label)}\s*:\s*\S/i) }
        end

        def section
          start = @headings.index { |found| found && found[2].casecmp?("Verification") }
          return [] unless start

          @lines[(start + 1)...section_end(start)]
        end

        def section_end(start)
          depth = @headings[start][1].size
          later = @headings.each_with_index.drop(start + 1)
          later.find { |found, _index| found && found[1].size <= depth }&.last || @lines.size
        end
      end
    end
  end
end
