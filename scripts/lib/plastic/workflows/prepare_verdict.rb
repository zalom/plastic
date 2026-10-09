# frozen_string_literal: true

require_relative "prepare_judge"

module Plastic
  module Workflows
    # Reads the intent and its judge rounds before a verdict is written: a missing or closed intent fails, both rounds used is the owner's step.
    class PrepareVerdict < CodeWorkflow
      sets :problem

      read "check the intent" do |context|
        context[:problem] = PrepareJudge.problem_for(context.retrieval.intent(context.intent_id), context.intent_id)
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }
      gate "intent %{intent_id} has used both review rounds; the owner takes the next step", stops: :refusal,
        pass: ->(context) { context.retrieval.verdicts(context.intent_id).size < Graph::Work::Verdict::ROUNDS }

      outcome :recording
    end
  end
end
