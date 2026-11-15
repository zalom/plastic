# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # Closure can be retried after the work commit but before lock cleanup. The files of the intent print after the close.
        class End < CodeWorkflow
          summary "Closes the intent and releases its lock."
          sets :ended

          read("check cleanup again") { |context| context[:ended] = false }

          step "close the intent and finish cleanup", done: ->(context) { context.ended == true },
            changes: { work: "The intent is marked done and its completion is saved", local: "The lock of the intent is released" } do |context|
            context.work.close_intent(context.intent_id)
            context.print("intent: #{context.intent_id} done")
            context[:ended] = true
          end

          outcome :done, offers: nil, because: "intent %{intent_id} is closed"
        end
      end
    end
  end
end
