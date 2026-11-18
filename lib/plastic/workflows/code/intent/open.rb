# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # Sets a future or parked intent open. Any other status is refused and stays as it is.
        class Open < CodeWorkflow
          clear_declarations

          OPENS = %w[future parked].freeze

          sets :intent, :problem

          read "read the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            status = context.intent&.status
            context[:problem] = "intent #{context.intent_id} is #{status}; only a future or parked intent opens" unless status.nil? || OPENS.include?(status)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
          gate "%{problem}", stops: :refusal,
            words: "the intent is not future or parked",
            pass: ->(context) { context.problem.nil? }

          step "open the intent", done: ->(context) { context.retrieval.intent(context.intent_id).status == "open" },
            changes: { work: "The intent is open" } do |context|
            context.work.open_intent(context.intent_id)
          end

          read "say what was written" do |context|
            context.print("opened: #{context.intent_id}")
          end

          outcome :done, offers: "plastic next", because: "intent %{intent_id} is open"
        end
      end
    end
  end
end
