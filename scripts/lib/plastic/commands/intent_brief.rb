# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the goal, the done criteria, the rulings with superseded ones
    # marked, the ready nodes and the usage of the node and edge commands.
    class IntentBrief < Routine
      intent_subject
      reads :work, :knowledge
      workflow :code_show_brief, next: :code_delivery_next
      workflow :code_delivery_next do
        on :done, next: :noop
        on :agent_needed, next: :agent_advance_delivery
      end
      workflow :agent_advance_delivery, next: :noop
    end
  end
end
