# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/work/completion/review"
require_relative "../../review_round"

module Plastic
  module Workflows
    module Code
      module Intent
        # Reads the intent and its judge rounds: a missing or closed intent fails, both rounds used is the owner's step.
        class Judge < CodeWorkflow
          summary "Checks that the intent can take a verdict."
          extend ReviewRound

          open_intent_gates "verdict"
          review_round_gate

          outcome :accepted, if: ->(context) { Plastic::Graph::Work::Completion::Review.of(context).counting? }, offers: "plastic intent end %{intent_id}",
            because: "intent %{intent_id} is accepted"
          outcome :judging, because: "the delivery waits for the verdict of the agent"
        end
      end
    end
  end
end
