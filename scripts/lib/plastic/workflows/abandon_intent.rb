# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # The abandoned close can be retried after the status write but before lock cleanup.
    class AbandonIntent < CodeWorkflow
      sets :abandon_ended

      read("check cleanup again") { |context| context[:abandon_ended] = false }

      step "abandon the intent and finish cleanup", done: ->(context) { context.abandon_ended == true } do |context|
        context.work.abandon_intent(context.intent_id)
        context.print("intent: #{context.intent_id} abandoned")
        context[:abandon_ended] = true
      end

      outcome :done, offers: nil, because: "intent %{intent_id} is abandoned"
    end
  end
end
