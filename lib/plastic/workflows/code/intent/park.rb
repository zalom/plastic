# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # Parks an intent in progress with the reason it waits, and writes one work log line.
        # Any other status fails and parks nothing.
        class Park < CodeWorkflow
          clear_declarations
          summary "Parks an intent in progress with its reason."

          sets :intent, :status

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
          gate "intent %{intent_id} is %{status}; only an intent in progress parks", stops: :failure,
            pass: ->(context) { context.status == "in_progress" }

          def self.parked?(context) = context.retrieval.intent(context.intent_id).status == "parked"

          step "park the intent", done: method(:parked?), changes: { work: "The intent is parked with its reason" } do |context|
            context.work.park_intent(context.intent_id, context.reason)
          end

          outcome :done, offers: "plastic next", because: "intent %{intent_id} is parked: %{reason}"
        end
      end
    end
  end
end
