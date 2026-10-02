# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Verifies the recorded prerequisites and records the judge's acceptance.
    class IntentEnd < Routine
      intent_subject
      option :judge, switch: "--judge WHO", text: "the accepting judge: tests, tool, agent or owner"
      option :evidence, switch: "--evidence PATH", text: "criterion evidence JSON inside the intent folder"
      writes :work
      reads :knowledge

      workflow :code_prepare_ending do
        on :closed, next: :code_close_intent
        on :ready, next: :code_close_intent
        on :agent_needed, next: :agent_finish_intent
      end
      workflow :agent_finish_intent, next: :noop
      workflow :code_close_intent, next: :noop
    end
  end
end
