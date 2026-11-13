# frozen_string_literal: true

require_relative "../../../../invalid"
require_relative "parsed"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        module Index
          # The links of one file, sorted into entries, clusters and problems.
          class Reading
            def initialize(links)
              @links = links
            end

            def parsed
              problems = unplaced + duplicates
              raise Invalid, "INDEX.md: #{problems.join("; ")}" if problems.any?

              Parsed.new(entries, clustered.map(&:member))
            end

            private

            def clustered = @links.select(&:clustered?)

            def listed = @links.select(&:status)

            # A listed intent comes first; one marked only in a cluster takes its first marker.
            def entries = (listed.map(&:entry) + clustered.select(&:marked_status).map(&:marked_entry)).uniq(&:intent_id)

            def unplaced = @links.reject(&:placed?).map(&:problem)

            def duplicates = listed.map(&:intent_id).tally.select { |_id, count| count > 1 }.keys.map { |id| "#{id} is listed twice" }
          end
        end
      end
    end
  end
end
