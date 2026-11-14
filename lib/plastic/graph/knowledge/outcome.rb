# frozen_string_literal: true

require_relative "outcome_forms"
require_relative "verification_section"

module Plastic
  module Graph
    module Knowledge
      # Reads one intent's outcome.md: the bullets under its Verification
      # heading, of any level, up to the next heading of the same or a higher
      # level. A bullet reads without its dash, checkbox and bold marks. No
      # document means no bullets.
      class Outcome
        def initialize(retrieval, intent_id)
          @bullets = VerificationSection.new(retrieval.fetch(intent_id, "outcome.md")&.body).bullets
        end

        # The messages that ask for the records this outcome lacks.
        def missing_records
          [(OutcomeForms.merge_message(rejected("Merged")) unless merged?), (format(OutcomeForms::MISSING, "Architecture map") unless architecture_map?)].compact
        end

        # The line of `label` when it is there but not in the form Plastic prints, as 'Label: value', else nil.
        def rejected(label)
          found = values(label).first
          "#{label}: #{found}" if found && !positive?(label)
        end

        def merged? = positive?("Merged")

        def architecture_map? = recorded?("Architecture map")

        def pull_request? = recorded?("Pull request")

        def approved? = positive?("Approved")

        def reverted? = recorded?("Reverted")

        def verification = @bullets

        private

        def recorded?(label) = values(label).any?

        def positive?(label) = values(label).any? { |value| OutcomeForms.in_form?(label, value) }

        def values(label) = @bullets.filter_map { |bullet| bullet[/\A#{Regexp.escape(label)}\s*:\s*(\S.*)\z/i, 1] }
      end
    end
  end
end
