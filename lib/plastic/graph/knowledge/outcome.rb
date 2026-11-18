# frozen_string_literal: true

require_relative "outcome_form"

module Plastic
  module Graph
    module Knowledge
      # Reads one intent's outcome.md: the bullets under its Verification
      # heading, of any level, up to the next heading of the same or a higher
      # level. A bullet reads without its dash, checkbox and bold marks. No
      # document means no bullets. A Delivered line counts only when the store
      # folder is given and holds the path it names in the intent folder.
      class Outcome
        HEADING = /\A(#+)\s*(.*?)\s*\z/
        BULLET = /\A[-*]\s*(?:\[[ xX]\]\s*)?(.+)\z/
        DELIVERY = %w[Merged Committed Delivered].freeze
        MISSING = "Add a line starting %s: to the Verification section of outcome.md and run plastic sync up."
        MISSING_DELIVERY = "Add one delivery line to the Verification section of outcome.md: '%s' for a merge, '%s' for a direct commit, " \
          "or '%s' for files that no version control holds. Then run plastic sync up."
        NOT_IN_FORM = "outcome.md says '%s', which is not a delivery line in the form '%s'. "
        NOT_IN_FOLDER = "outcome.md says '%s', but the intent folder holds no %s. "
        FIX = "Fix that line or put the delivered files in place, then run plastic sync up."

        def initialize(retrieval, intent_id, folder: nil)
          @lines = retrieval.fetch(intent_id, "outcome.md")&.body.to_s.lines.map(&:chomp)
          @headings = @lines.map { |line| line.match(HEADING) }
          @intent_folder = folder && retrieval.intent(intent_id)&.then { |intent| folder.path(intent.dir) }
        end

        # The messages that ask for the records this outcome lacks.
        def missing_records = [(delivery_message unless delivery_recorded?), (format(MISSING, "Architecture map") unless map_recorded?)].compact

        # The line of `label` when it is there but does not count, as 'Label: value', else nil.
        def rejected(label)
          found = values(label).first
          "#{label}: #{found}" if found && !positive?(label)
        end

        # The first delivery line that is there but does not count, as 'Label: value', else nil.
        def delivery_rejection = DELIVERY.lazy.filter_map { |label| rejected(label) }.first

        def delivery_recorded? = DELIVERY.any? { |label| positive?(label) }

        def merged? = positive?("Merged")

        def committed? = positive?("Committed")

        # Files alone need no architecture map; a merge, a commit or no delivery line yet do.
        def map_recorded? = architecture_map? || (positive?("Delivered") && !merged? && !committed?)

        def architecture_map? = recorded?("Architecture map")

        def pull_request? = recorded?("Pull request")

        def approved? = positive?("Approved")

        def reverted? = recorded?("Reverted")

        def verification = section.filter_map { |line| line[BULLET, 1]&.delete("*")&.strip }

        # The sentence that names the first delivery line that does not count and why, else "".
        def delivery_finding
          found = delivery_rejection
          return "" unless found

          label, value = found.split(": ", 2)
          path = OutcomeForm.delivered_path(value) if OutcomeForm.in_form?(label, value)
          path ? format(NOT_IN_FOLDER, found, path) : format(NOT_IN_FORM, found, OutcomeForm.shown(label))
        end

        private

        def recorded?(label) = values(label).any?

        def positive?(label) = values(label).any? { |value| counts?(label, value) }

        def counts?(label, value) = OutcomeForm.in_form?(label, value) && (label != "Delivered" || in_folder?(OutcomeForm.delivered_path(value)))

        def in_folder?(path) = !@intent_folder.nil? && !path.split("/").include?("..") && File.exist?(File.join(@intent_folder, path))

        def values(label) = verification.filter_map { |bullet| bullet[/\A#{Regexp.escape(label)}\s*:\s*(\S.*)\z/i, 1] }

        def delivery_message
          finding = delivery_finding
          finding.empty? ? format(MISSING_DELIVERY, *DELIVERY.map { |label| OutcomeForm.shown(label) }) : finding + FIX
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
