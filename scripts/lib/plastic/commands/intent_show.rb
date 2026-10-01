# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints one intent: its status, criteria count, open decisions,
    # rulings, nodes and last savepoint lines.
    class IntentShow < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent"
      reads :work, :knowledge
      workflow :code_show_intent, next: :noop
    end
  end
end
