# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # The form a Merged or an Approved line of outcome.md must take to count, and the messages that name it.
      module OutcomeForms
        FORMS = {
          "Merged" => /\A(?:\S+ into )?\S+ at \D*\d/,
          "Approved" => /\A(?:by )?\S.*? on \d{4}-\d{2}-\d{2}\b/
        }.freeze
        SHOWN = {
          "Merged" => "Merged: <branch> into <base> at <commit or pull request>",
          "Approved" => "Approved: <person> on <YYYY-MM-DD>"
        }.freeze
        PLACEHOLDER = /[<>]/
        MISSING = "Add a line starting %s: to the Verification section of outcome.md and run plastic sync up."
        NOT_IN_FORM = "outcome.md records '%s', which is not in the form that counts. " \
          "Write the line as '%s' with every part filled, then run plastic sync up."

        def self.in_form?(label, value) = FORMS.fetch(label).match?(value) && !PLACEHOLDER.match?(value)

        # The message for a Merged line: the form it must take when a line is there, else the line to add.
        def self.merge_message(found) = found ? format(NOT_IN_FORM, found, SHOWN.fetch("Merged")) : format(MISSING, "Merged")
      end
    end
  end
end
