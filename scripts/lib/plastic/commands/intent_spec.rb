# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the grilling method, then one intent's open decisions.
    class IntentSpec < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent"
      reads :knowledge

      workflow :code_show_spec, next: :noop
    end
  end
end
