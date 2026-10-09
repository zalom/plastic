# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Runs the five findings of one intent's work graph and its spec.
    class GraphCheck < Routine
      intent_subject
      reads :work
      workflow :code_check_graph, next: :code_delivery_next
      workflow :code_delivery_next do
        on :done, next: :noop
        on :nothing, next: :noop
        on :agent_needed, next: :agent_advance_delivery
      end
      workflow :agent_advance_delivery, next: :noop
    end
  end
end
