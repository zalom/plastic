# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the steps that start a reasoning judge for an intent, and where its verdict is recorded.
    class IntentJudge < Routine
      intent_subject

      workflow :code_prepare_judge do
        on :judging, next: :agent_judge_intent
        on :accepted, next: :noop
      end
      workflow :agent_judge_intent, next: :noop
    end
  end
end
