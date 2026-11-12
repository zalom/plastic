# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Graph
      # Runs the five findings of one intent's work graph and its spec.
      class Check < Routine
        intent_subject
        reads :work
        workflow :code_check_graph, next: :noop
      end
    end
  end
end
