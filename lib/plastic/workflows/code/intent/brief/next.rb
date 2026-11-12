# frozen_string_literal: true

require_relative "../brief"
require_relative "../../../../code_workflow"
require_relative "../../../../graph/work/delivery_action"

module Plastic
  module Workflows
    module Code
      module Intent
        class Brief
          # Resolves a graph read into an action or a checked harness handoff.
          class Next < CodeWorkflow
            sets :next_command, :why, :handoff_text

            read "choose the delivery action" do |context|
              context[:next_command], context[:why], context[:handoff_text] = Plastic::Graph::Work::DeliveryAction.new(context.retrieval, context.intent_id).call
            end

            outcome :agent_needed, if: ->(context) { !context.handoff_text.nil? }
            outcome :nothing, if: ->(context) { context.next_command.nil? }, offers: nil, because: "%{why}"
            outcome :done, offers: "%{next_command}", because: "%{why}"
          end
        end
      end
    end
  end
end
