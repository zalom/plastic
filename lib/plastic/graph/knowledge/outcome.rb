# frozen_string_literal: true

require "forwardable"
require_relative "outcome_form"
require_relative "outcome_delivery"

module Plastic
  module Graph
    module Knowledge
      # Reads one intent's outcome.md: the bullets under its Verification
      # heading, of any level, up to the next heading of the same or a higher
      # level. A bullet reads without its dash, checkbox and bold marks. No
      # document means no bullets. The delivery lines are read by OutcomeDelivery,
      # which needs the store folder to find delivered files.
      class Outcome
        extend Forwardable

        HEADING = /\A(#+)\s*(.*?)\s*\z/
        BULLET = /\A[-*]\s*(?:\[[ xX]\]\s*)?(.+)\z/
        MISSING = "Add a line starting %s: to the Verification section of outcome.md and run plastic sync up."

        def_delegator :@delivery, :recorded?, :delivery_recorded?
        def_delegator :@delivery, :rejection, :delivery_rejection
        def_delegator :@delivery, :finding, :delivery_finding
        def_delegators :@delivery, :merged?, :committed?

        def initialize(retrieval, intent_id, folder: nil)
          @lines = retrieval.fetch(intent_id, "outcome.md")&.body.to_s.lines.map(&:chomp)
          @headings = @lines.map { |line| line.match(HEADING) }
          @delivery = OutcomeDelivery.new(self, folder&.path(retrieval.intent(intent_id).dir))
        end

        # The messages that ask for the records this outcome lacks.
        def missing_records = [(@delivery.message unless delivery_recorded?), (format(MISSING, "Architecture map") unless map_recorded?)].compact

        # The line of `label` when it is there but not in its form, as 'Label: value', else nil.
        def rejected(label)
          found = values(label).first
          "#{label}: #{found}" if found && !positive?(label)
        end

        def map_recorded? = architecture_map? || !@delivery.map_needed?

        def architecture_map? = recorded?("Architecture map")

        def pull_request? = recorded?("Pull request")

        def approved? = positive?("Approved")

        def reverted? = recorded?("Reverted")

        def verification = section.filter_map { |line| line[BULLET, 1]&.delete("*")&.strip }

        # The values written after `label:` under Verification, in order.
        def values(label) = verification.filter_map { |bullet| bullet[/\A#{Regexp.escape(label)}\s*:\s*(\S.*)\z/i, 1] }

        private

        def recorded?(label) = values(label).any?

        def positive?(label) = values(label).any? { |value| OutcomeForm.in_form?(label, value) }

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
