# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Prints one intent: its status, criteria count, open decisions,
      # rulings, nodes and last savepoint lines.
      class Show < Routine
        intent_subject
        reads :work, :knowledge
        workflow :code_show_intent, next: :noop
      end
    end
  end
end
