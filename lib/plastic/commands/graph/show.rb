# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Graph
      # Prints one intent's nodes and edges from the rows. It reads and writes nothing.
      class Show < Routine
        intent_subject
        reads :work

        workflow :code_show_graph, next: :noop
      end
    end
  end
end
