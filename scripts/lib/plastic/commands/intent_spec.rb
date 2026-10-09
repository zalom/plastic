# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the grilling method, then one intent's open decisions.
    class IntentSpec < Routine
      intent_subject
      reads :knowledge

      workflow :code_show_spec do
        on :open, next: :noop
        on :no_criterion, next: :noop
        on :done, next: :noop
        on :agent_needed, next: :agent_advance_delivery
      end
      workflow :agent_advance_delivery, next: :noop
    end
  end
end
