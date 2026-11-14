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
        NEGATIVE = %r{\A(?:-\z|(?:no|not|none|pending|n/a|tbd|false)[[:punct:]]*(?:\s|\z))}i
        MISSING = "Add a line starting %s: to the Verification section of outcome.md and run plastic sync up."
        NOT_A_MERGE = "outcome.md records '%s', which is not a merge. Merge the pull request, then replace the line with " \
          "'Merged: <branch> into <base> at <commit or pull request>' and run plastic sync up."

        def initialize(retrieval, intent_id)
          @lines = retrieval.fetch(intent_id, "outcome.md")&.body.to_s.lines.map(&:chomp)
          @headings = @lines.map { |line| line.match(HEADING) }
        end

        # The messages that ask for the records this outcome lacks.
        def missing_records
          [(merge_message unless merged?), (format(MISSING, "Architecture map") unless architecture_map?)].compact
        end

        # The Merged line when it is there and says there is no merge, else nil.
        def negative_merge
          found = values("Merged").first
          "Merged: #{found}" if found && !merged?
        end

        def merged? = positive?("Merged")

        def architecture_map? = recorded?("Architecture map")

        def pull_request? = recorded?("Pull request")

        def approved? = positive?("Approved")

        def reverted? = recorded?("Reverted")

        def verification = section.filter_map { |line| line[BULLET, 1]&.delete("*")&.strip }

        private

        def recorded?(label) = values(label).any?

        def positive?(label) = values(label).grep_v(NEGATIVE).any?

        def values(label) = verification.filter_map { |bullet| bullet[/\A#{Regexp.escape(label)}\s*:\s*(\S.*)\z/i, 1] }

        def merge_message = negative_merge ? format(NOT_A_MERGE, negative_merge) : format(MISSING, "Merged")

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
