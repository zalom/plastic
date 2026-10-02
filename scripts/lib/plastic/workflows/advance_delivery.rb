# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The harness performs judgment and records the result through commands.
    class AdvanceDelivery < AgentWorkflow
      step "advance the delivery", done: ->(context) { context.handoff_text.nil? }, say: "%{handoff_text}"
      outcome :handoff, offers: nil, because: "%{why}"
      outcome :done, offers: nil, because: "the delivery instruction has been handled"
    end
  end
end
