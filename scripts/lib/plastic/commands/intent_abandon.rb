# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Abandons an intent that will not ship once outcome.md records the revert, and hands over the revert steps until then.
    class IntentAbandon < Routine
      intent_subject
      writes :work
      reads :knowledge

      workflow :code_prepare_abandon do
        on :reverting, next: :agent_revert_intent
        on :abandoning, next: :code_abandon_intent
      end
      workflow :agent_revert_intent, next: :noop
      workflow :code_abandon_intent do
        on :done, next: :agent_wind_down_intent
      end
      workflow :agent_wind_down_intent, next: :noop
    end
  end
end
