# frozen_string_literal: true

require_relative "../../../agent_workflow"

module Plastic
  module Workflows
    module Agent
      module Architecture
        # The agent regenerates the architecture map with the tool it chose.
        # Plastic runs no tool and reads no result, so the step is never done on its own.
        class Refresh < AgentWorkflow
          step "refresh the architecture map", done: ->(_context) { false },
            say: "Regenerate the project's architecture map with an architecture mapping tool such as Enola; the choice of " \
              "tool is yours. Read the new map for context, together with the project's AGENTS.md, before you plan code work. " \
              "Plastic runs no tool and asks for no record of the map."

          outcome :handoff, offers: nil, because: "the agent refreshes the architecture map with its own tool"
          outcome :done, offers: nil, because: "the architecture map was refreshed"
        end
      end
    end
  end
end
