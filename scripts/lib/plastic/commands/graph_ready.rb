# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Lists the nodes ready to claim: open, with every need done.
    class GraphReady < Routine
      intent_subject
      reads :work
      workflow :code_ready_graph, next: :code_delivery_next
      workflow :code_delivery_next do
        on :done, next: :noop
        on :nothing, next: :noop
        on :agent_needed, next: :agent_advance_delivery
      end
      workflow :agent_advance_delivery, next: :noop
    end
  end
end
