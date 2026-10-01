# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the goal, the done criteria, the rulings with superseded ones
    # marked, the ready nodes and the usage of the node and edge commands.
    class IntentBrief < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent"
      reads :work, :knowledge
      workflow :code_show_brief, next: :noop
    end
  end
end
