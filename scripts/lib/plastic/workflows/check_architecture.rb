# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The agent checks the architecture map with the tool it chose. Plastic
    # runs no tool and reads no result, so the step is never done on its own.
    class CheckArchitecture < AgentWorkflow
      step "check the architecture map", done: ->(_context) { false },
        say: "Check whether the project has an architecture map and whether it describes the source as it is now. Use an " \
          "architecture mapping tool such as Enola; the choice of tool is yours. When the map is current, read it for " \
          "context. When it is missing or older than the source, refresh it."

      outcome :handoff, offers: "plastic architecture refresh", because: "the agent judges whether the architecture map is current"
      outcome :done, offers: nil, because: "the architecture map was checked"
    end
  end
end
