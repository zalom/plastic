# frozen_string_literal: true

require_relative "../../../agent_workflow"

module Plastic
  module Workflows
    module Agent
      module Shared
        # The harness performs judgment and records the result through commands.
        class AdvanceDelivery < AgentWorkflow
          summary "Hands the agent the next step of the delivery."
          step "advance the delivery", done: ->(context) { context.handoff_text.nil? }, say: "%{handoff_text}",
            gets: "The instruction for the next step of the delivery: the owner's go-ahead while none is recorded, then the step the state of the intent calls for"
          outcome :handoff, offers: nil, because: "%{why}", ends_when: "the delivery has a next step for the agent, and the reason names the state of the intent that chose it"
          outcome :done, offers: nil, because: "the delivery instruction has been handled"
        end
      end
    end
  end
end
