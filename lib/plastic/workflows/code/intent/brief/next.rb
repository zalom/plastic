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
            summary "Turns a read of the graph into the next action or a handoff to the harness."
            sets :next_command, :why, :handoff_text

            read "choose the delivery action" do |context|
              context[:next_command], context[:why], context[:handoff_text] = Plastic::Graph::Work::DeliveryAction.new(context.retrieval, context.intent_id).call
            end

            outcome :agent_needed, if: ->(context) { !context.handoff_text.nil? }, because: "the agent takes the next step of the brief"
            outcome :nothing, if: ->(context) { context.next_command.nil? }, offers: nil, because: "%{why}", ends_when: "the brief has no next command"
            outcome :done, offers: "%{next_command}", because: "%{why}", ends_when: "the brief names the next command and the reason for it"
          end
        end
      end
    end
  end
end
