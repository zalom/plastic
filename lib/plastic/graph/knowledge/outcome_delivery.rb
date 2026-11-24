# frozen_string_literal: true

require_relative "outcome_form"

module Plastic
  module Graph
    module Knowledge
      # The delivery lines of one outcome.md: a merge, a direct commit, or files that no version
      # control holds. A Delivered line counts only when the intent folder is known and holds the
      # path it names, with no step out of that folder.
      class OutcomeDelivery
        LABELS = { "Merged" => :merged?, "Committed" => :committed?, "Delivered" => :files? }.freeze
        MISSING = "Add one delivery line to the Verification section of outcome.md: '%s' for a merge, '%s' for a direct commit, " \
          "or '%s' for files that no version control holds. Then run plastic store sync up."
        NOT_IN_FORM = "outcome.md says '%s', which is not a delivery line in the form '%s'. "
        NOT_IN_FOLDER = "outcome.md says '%s', but the intent folder holds no %s. "
        FIX = "Fix that line or put the delivered files in place, then run plastic store sync up."

        def initialize(outcome, intent_folder)
          @outcome = outcome
          @intent_folder = intent_folder
        end

        def recorded? = merged? || committed? || files?

        def merged? = in_form?("Merged")

        def committed? = in_form?("Committed")

        def files? = @outcome.values("Delivered").any? { |value| delivered_file?(value) }

        # The first delivery line that is there but does not count, as 'Label: value', else nil.
        def rejection = LABELS.lazy.filter_map { |label, counted| line(label) unless public_send(counted) }.first

        # The sentence that names the first delivery line that does not count and why, else "".
        def finding
          found = rejection
          return "" unless found

          label, value = found.split(": ", 2)
          path = OutcomeForm.delivered_path(value) if OutcomeForm.in_form?(label, value)
          path ? format(NOT_IN_FOLDER, found, path) : format(NOT_IN_FORM, found, OutcomeForm.shown(label))
        end

        # The message that asks for the delivery line, naming the one that does not count when there is one.
        def message
          found = finding
          found.empty? ? format(MISSING, *LABELS.keys.map { |label| OutcomeForm.shown(label) }) : found + FIX
        end

        private

        def line(label) = @outcome.values(label).first&.then { |value| "#{label}: #{value}" }

        def in_form?(label) = @outcome.values(label).any? { |value| OutcomeForm.in_form?(label, value) }

        def delivered_file?(value) = OutcomeForm.in_form?("Delivered", value) && in_folder?(OutcomeForm.delivered_path(value))

        def in_folder?(path) = !@intent_folder.nil? && !path.split("/").include?("..") && File.exist?(File.join(@intent_folder, path))
      end
    end
  end
end
