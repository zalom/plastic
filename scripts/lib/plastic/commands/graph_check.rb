# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Runs the five findings of one intent's work graph and its spec.
    class GraphCheck < Routine
      intent_subject
      reads :work
      workflow :code_check_graph, next: :noop
    end
  end
end
