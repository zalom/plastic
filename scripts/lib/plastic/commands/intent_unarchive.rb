# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Puts an archived intent's directory back on the checkout exactly as it was archived.
    class IntentUnarchive < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the archived intent to restore"
      writes :work, :knowledge, :references
      prints :index
      previews

      workflow :code_restore_intent, next: :noop
    end
  end
end
