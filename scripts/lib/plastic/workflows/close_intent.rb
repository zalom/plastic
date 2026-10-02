# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Closure can be retried after the work commit but before lock cleanup.
    class CloseIntent < CodeWorkflow
      sets :ended

      read("check cleanup again") { |context| context[:ended] = false }

      step "close the intent and finish cleanup", done: ->(context) { context.ended == true } do |context|
        context.work.close_intent(context.intent_id, judge: context.judge, evidence: context.attestation)
        context.work.print_index
        context.print("intent: #{context.intent_id} done")
        context[:ended] = true
      end

      outcome :done, offers: nil, because: "intent %{intent_id} is closed"
    end
  end
end
