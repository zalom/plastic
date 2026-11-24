# frozen_string_literal: true

require_relative "../../../agent_workflow"

module Plastic
  module Workflows
    module Agent
      module Intent
        # The agent undoes what the intent changed and records that in outcome.md. Plastic runs no version control command.
        class Abandon < AgentWorkflow
          summary "Has the agent undo what the intent changed and record it in outcome.md."
          step "revert what intent %{intent_id} changed", done: ->(context) { context.reverted },
            say: "Use version control, such as Git, as the project's AGENTS.md or CLAUDE.md defines it, " \
              "or as the project's history shows when neither does: " \
              "undo what intent %{intent_id} changed, close or delete its branch and worktree, " \
              "and revert any commit that reached the base. " \
              "Plastic runs no version control command; it records what you write."
          step "record the revert", done: ->(context) { context.reverted },
            say: "Write why the intent is dropped with plastic intent outcome %{intent_id} --from FILE. " \
              "Record the reason with plastic intent note %{intent_id} 'superseded by intent <id>' --kind Abandoned, " \
              "or plastic intent note %{intent_id} 'dropped because <reason>' --kind Abandoned, " \
              "and the revert with plastic intent note %{intent_id} '<what was undone, or nothing delivered>' --kind Reverted. " \
              "Then run plastic intent abandon %{intent_id} again."

          outcome :handoff, offers: nil, because: "the agent reverts the intent's changes and records it in outcome.md"
          outcome :done, offers: nil, because: "the revert is recorded"
        end
      end
    end
  end
end
