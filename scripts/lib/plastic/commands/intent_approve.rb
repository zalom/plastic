# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Writes the owner's go-ahead for an intent. `plastic auto` refuses an intent without it.
    class IntentApprove < Routine
      intent_subject
      writes :work
      prints :intent

      workflow :code_approve_intent, next: :noop
    end
  end
end
