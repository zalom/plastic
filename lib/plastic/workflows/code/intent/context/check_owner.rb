# frozen_string_literal: true

require_relative "../context"
require_relative "../../../../code_workflow"
require_relative "../../../intent_id_format"

module Plastic
  module Workflows
    module Code
      module Intent
        class Context
          # Confirms that a context request names an existing intent in its owning store.
          class CheckOwner < CodeWorkflow
            [facts, steps, outcomes].each(&:clear)

            sets :intent

            read "find the owning intent" do |context|
              IntentIdFormat.validate(context.intent_id)
              context[:intent] = !context.retrieval.intent(context.intent_id).nil?
            end

            gate "no intent %{intent_id} in owning store", stops: :failure, pass: ->(context) { context.intent }

            outcome :submit, if: ->(context) { context.from }, because: "a context submission was given"
            outcome :read, because: "no submission was given"
          end
        end
      end
    end
  end
end
