# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # A close that stopped after the status write can be retried. The files of the intent print after the close.
        class End < CodeWorkflow
          summary "Closes the intent and ends its run of work."
          sets :ended

          read("forget the close of an earlier call") { |context| context[:ended] = false }

          step "close the intent", done: ->(context) { context.ended == true },
            changes: { work: "The intent is marked done, its completion is saved and its driver claim is released" } do |context|
            context.work.close_intent(context.intent_id)
            context.print("intent: #{context.intent_id} done")
            held = context.work.release_driver(context.intent_id)
            context.print("driver claim: released, held by session #{held}") if held
            context[:ended] = true
          end

          outcome :done, offers: nil, because: "intent %{intent_id} is closed"
        end
      end
    end
  end
end
