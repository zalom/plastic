# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/work/verdict"

module Plastic
  module Workflows
    # Reads the intent and its judge rounds: a missing or closed intent fails, both rounds used is the owner's step.
    class PrepareJudge < CodeWorkflow
      sets :problem

      read "check the intent" do |context|
        intent = context.retrieval.intent(context.intent_id)
        context[:problem] = problem_for(intent, context.intent_id)
      end

      def self.problem_for(intent, intent_id)
        return "no intent #{intent_id} in this store" unless intent

        "intent #{intent_id} is #{intent.status}; it takes no verdict" if %w[done abandoned].include?(intent.status)
      end

      def self.latest(context) = context.retrieval.verdicts(context.intent_id).max_by(&:round)

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }
      gate "intent %{intent_id} has used both review rounds; the owner takes the next step", stops: :refusal,
        pass: ->(context) { context.retrieval.verdicts(context.intent_id).size < Graph::Work::Verdict::ROUNDS }

      outcome :recording, if: ->(context) { context.verdict }
      outcome :accepted, if: ->(context) { latest(context)&.verdict == "accept" }, offers: "plastic intent end %{intent_id}",
        because: "intent %{intent_id} is accepted"
      outcome :judging
    end
  end
end
