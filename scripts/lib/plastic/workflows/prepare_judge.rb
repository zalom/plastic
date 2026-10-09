# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Reads the intent and its judge rounds: a missing or closed intent fails, both rounds used is the owner's step.
    class PrepareJudge < CodeWorkflow
      sets :problem

      read "check the intent" do |context|
        context[:problem] = context.work.open_intent_problem(context.intent_id, "verdict")
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }
      def self.latest(context) = context.retrieval.verdicts(context.intent_id).max_by(&:round)

      gate "intent %{intent_id} has used both review rounds; the owner takes the next step", stops: :refusal,
        pass: ->(context) { context.work.rounds_left?(context.intent_id) }

      outcome :accepted, if: ->(context) { latest(context)&.verdict == "accept" }, offers: "plastic intent end %{intent_id}",
        because: "intent %{intent_id} is accepted"
      outcome :judging
    end
  end
end
