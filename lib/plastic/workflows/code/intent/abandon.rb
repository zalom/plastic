# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # An abandon that stopped after the status write can be retried.
        class Abandon < CodeWorkflow
          summary "Marks the intent abandoned and ends its run of work."
          sets :abandon_ended

          read("forget the abandon of an earlier call") { |context| context[:abandon_ended] = false }

          step "abandon the intent", done: ->(context) { context.abandon_ended == true },
            changes: { work: "The intent is marked abandoned" } do |context|
            context.work.abandon_intent(context.intent_id)
            context.print("intent: #{context.intent_id} abandoned")
            context[:abandon_ended] = true
          end

          outcome :done, offers: nil, because: "intent %{intent_id} is abandoned"
        end
      end
    end
  end
end
