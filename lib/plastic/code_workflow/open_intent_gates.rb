# frozen_string_literal: true

module Plastic
  class CodeWorkflow < Workflow
    # The gates of a workflow that writes into an intent that takes `takes`: a missing intent fails, an intent
    # that is done or abandoned is refused. One place gives every such workflow the same two exits.
    module OpenIntentGates
      def open_intent_gates(takes)
        sets :problem
        read("check the intent") { |context| context[:problem] = context.work.open_intent_problem(context.intent_id, takes) }
        gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { intent_found?(context) }
        gate "%{problem}", stops: :refusal, words: "the intent is done or abandoned", pass: ->(context) { context.problem.nil? }
      end

      def intent_found?(context) = !context.retrieval.intent(context.intent_id).nil?
    end
  end
end
