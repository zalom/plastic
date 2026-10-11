# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # After a first install, the agent may offer Enola to the person. Plastic
    # runs no Enola installer and keeps no answer, so a reinstall offers nothing.
    class OfferEnola < AgentWorkflow
      step "offer Enola", done: ->(context) { context.reinstall },
        say: "Enola maps the code architecture of a project. It is optional: Plastic works without it. To install it, " \
          "run its official installer: curl -fsSL https://raw.githubusercontent.com/enola-labs/enola/main/install.sh | sh"

      outcome :handoff, offers: "plastic init", because: "Enola is optional; plastic init installs Plastic into the harnesses the person picks"
      outcome :done, offers: "plastic version", because: "a reinstall syncs the files and offers nothing more"
    end
  end
end
