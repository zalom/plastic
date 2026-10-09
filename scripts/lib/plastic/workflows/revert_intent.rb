# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The agent undoes what the intent changed and records that in outcome.md. Plastic runs no version control command.
    class RevertIntent < AgentWorkflow
      step "revert what intent %{intent_id} changed", done: ->(context) { context.reverted },
        say: "Undo what intent %{intent_id} changed with your own version control tool: close or delete its branch and worktree, and revert any commit that reached the base. " \
          "Plastic runs no version control command; it records what you write."
      step "record the revert", done: ->(context) { context.reverted },
        say: "Write in %{intent_folder}/outcome.md why the intent is dropped, and add the line '- Reverted: <what was undone, or nothing delivered>' under ## Verification. " \
          "Run plastic sync up and then plastic intent abandon %{intent_id} again."

      outcome :handoff, offers: nil, because: "the agent reverts the intent's changes and records it in outcome.md"
      outcome :done, offers: nil, because: "the revert is recorded"
    end
  end
end
