# frozen_string_literal: true

require_relative "outcome_section"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # The Notes section of an intent outcome.
        class Notes
          HEADING = "## Notes"
          KINDS = %w[Review Commit Report].freeze

          def self.for(body) = new(OutcomeSection.for(body, HEADING))

          def initialize(section)
            @section = section
          end

          def add(kind, text) = @section.add("- #{kind}: #{text}")
        end
      end
    end
  end
end
