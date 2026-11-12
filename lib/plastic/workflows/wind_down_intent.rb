# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The agent stops what the intent started. Plastic runs and stops nothing.
    class WindDownIntent < AgentWorkflow
      step "stop what intent %{intent_id} started", done: ->(_context) { false },
        say: "Stop the processes and the agents that intent %{intent_id} started: servers, watchers, background jobs and subagents. " \
          "Plastic runs none of them and stops none of them."

      outcome :handoff, offers: nil, because: "the agent stops the processes and agents the intent started"
      outcome :done, offers: nil, because: "nothing the intent started is left running"
    end
  end
end
