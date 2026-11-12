# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "review_round"

module Plastic
  module Workflows
    # Reads the intent and its judge rounds before a verdict is written: a missing or closed intent fails, both rounds used is the owner's step.
    class PrepareVerdict < CodeWorkflow
      sets :problem

      read "check the intent" do |context|
        context[:problem] = context.work.open_intent_problem(context.intent_id, "verdict")
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }
      gate ReviewRound::MESSAGE, stops: :refusal,
        pass: ->(context) { context.work.rounds_left?(context.intent_id) }

      outcome :recording
    end
  end
end
