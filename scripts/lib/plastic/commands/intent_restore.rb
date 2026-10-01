# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints an archived intent's folder back from its rows.
    class IntentRestore < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent to restore"
      writes :work, :knowledge, :references

      workflow :code_restore_intent, next: :noop
    end
  end
end
