# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Closes a delivered intent once the rows, the verdict and outcome.md allow it, and hands over what is missing.
    class IntentEnd < Routine
      intent_subject
      writes :work
      prints :intent
      reads :knowledge

      workflow :code_prepare_ending do
        on :unverified, next: :agent_check_merge
        on :closed, next: :code_close_intent
        on :ready, next: :code_close_intent
        on :agent_needed, next: :agent_finish_intent
      end
      workflow :agent_finish_intent, next: :noop
      workflow :agent_check_merge, next: :noop
      workflow :code_close_intent do
        on :done, next: :agent_wind_down_intent
      end
      workflow :agent_wind_down_intent, next: :noop
    end
  end
end
