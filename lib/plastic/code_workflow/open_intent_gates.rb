# frozen_string_literal: true

require_relative "../workflow"

module Plastic
  class CodeWorkflow < Workflow
    # The gates of a workflow that writes into an intent that takes `takes`: a missing intent fails, an intent
    # that is done or abandoned is refused. One place gives every such workflow the same two exits.
    module OpenIntentGates
      FIND = lambda do |context, takes|
        id = context.intent_id
        context[:intent] = context.retrieval.intent(id)
        context[:problem] = context.work.open_intent_problem(id, takes)
      end

      def open_intent_gates(takes)
        sets :intent, :problem
        read("check the intent") { |context| FIND.call(context, takes) }
        gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
        gate "%{problem}", stops: :refusal, words: "the intent is done or abandoned", pass: ->(context) { context.problem.nil? }
      end
    end
  end
end
