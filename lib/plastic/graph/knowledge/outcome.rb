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
        NEGATIVE = %w[no not none pending n/a tbd false].freeze

        def initialize(retrieval, intent_id)
          document = retrieval.documents(intent_id).find { |candidate| candidate.path == "outcome.md" }
          @lines = document ? document.body.lines.map(&:chomp) : []
          @headings = @lines.map { |line| line.match(HEADING) }
        end

        # The messages that ask for the records this outcome lacks.
        def missing_records = [merged_message, architecture_map_message].compact

        # The Merged line when it is there and says there is no merge, else nil.
        def negative_merge
          found = found_value("Merged")
          "Merged: #{found}" if found && !merged?
        end

        def merged? = positive?("Merged")

        def architecture_map? = recorded?("Architecture map")

        def pull_request? = recorded?("Pull request")

        def approved? = positive?("Approved")

        def reverted? = recorded?("Reverted")

        def verification = section.filter_map { |line| line[BULLET, 1]&.delete("*")&.strip }

        private

        def recorded?(label) = !found_value(label).nil?

        def positive?(label) = values(label).any? { |value| !negative?(value) }

        def found_value(label) = values(label).first

        def values(label) = verification.filter_map { |bullet| bullet[/\A#{Regexp.escape(label)}\s*:\s*(\S.*)\z/i, 1] }

        def negative?(value) = value == "-" || NEGATIVE.include?(value.split.first.downcase.sub(/[[:punct:]]+\z/, ""))

        def merged_message
          return if merged?

          if negative_merge
            "outcome.md records '#{negative_merge}', which is not a merge. Merge the pull request, then replace the line with " \
              "'Merged: <branch> into <base> at <commit or pull request>' and run plastic sync up."
          else
            "Add a line starting Merged: to the Verification section of outcome.md and run plastic sync up."
          end
        end

        def architecture_map_message
          "Add a line starting Architecture map: to the Verification section of outcome.md and run plastic sync up." unless architecture_map?
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
