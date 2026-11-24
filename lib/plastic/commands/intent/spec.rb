# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Writes spec.md from the file that --from names, then prints the grilling method and one intent's open decisions.
      class Spec < Routine
        intent_subject
        option :from, switch: "--from FILE", text: "a file that holds the whole spec.md, written as its new revision; refused when it lacks a section of the layout or the intent is closed"
        reads :work, :knowledge
        writes :knowledge, :retrieval
        prints :intent

        workflow :code_write_spec do
          on :written, next: :code_show_spec
          on :kept, next: :code_show_spec
        end

        workflow :code_show_spec do
          on :open, next: :noop
          on :no_criterion, next: :noop
          on :approved, next: :noop
          on :unapproved, next: :noop
        end

        private

        # A call that writes no spec prints nothing, so a file changed by hand stops only a call with --from.
        def refuse_hand_edits(ctx) = parsed[:from] && super
      end
    end
  end
end
