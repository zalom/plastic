# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The agent regenerates the architecture map with the tool it chose.
    # Plastic runs no tool and reads no result, so the step is never done on its own.
    class RefreshArchitecture < AgentWorkflow
      step "refresh the architecture map", done: ->(_context) { false },
        say: "Regenerate the project's architecture map with an architecture mapping tool such as Enola; the choice of " \
          "tool is yours. Read the new map for context. When you deliver an intent, note the tool, the source revision " \
          "the map describes, what it covers and what it leaves out under Verification in outcome.md."

      outcome :handoff, offers: nil, because: "the agent refreshes the architecture map with its own tool"
      outcome :done, offers: nil, because: "the architecture map was refreshed"
    end
  end
end
