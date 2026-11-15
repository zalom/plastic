# frozen_string_literal: true

require_relative "../../agent_workflow"

module Plastic
  module Workflows
    module Agent
      # After a first install, the agent may offer Enola to the person. Plastic
      # runs no Enola installer and keeps no answer, so a reinstall offers nothing.
      class Install < AgentWorkflow
        ENOLA_VERSION = "0.4.39"

        step "offer Enola", done: ->(context) { context.reinstall },
          say: "Enola maps the code architecture of a project. It is optional: Plastic works without it. To install it, " \
            "read the release notes and run its installer from " \
            "https://github.com/enola-labs/enola/releases/tag/v#{ENOLA_VERSION}, then set up Enola's hooks and its MCP server for this harness"

        outcome :handoff, offers: "plastic init", because: "Enola is optional; plastic init installs Plastic into the harnesses the person picks"
        outcome :done, offers: "plastic version", because: "a reinstall syncs the files and offers nothing more"
      end
    end
  end
end
