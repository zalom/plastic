# frozen_string_literal: true

require_relative "../end"
require_relative "../../../../agent_workflow"

module Plastic
  module Workflows
    module Agent
      module Intent
        class End
          # The agent merges the pull request of the intent and confirms the architecture map,
          # then records both under Verification in outcome.md. Plastic runs no version
          # control command and records what the agent writes.
          class CheckMerge < AgentWorkflow
            step "merge the code", done: ->(context) { context.merge_recorded },
              say: "%{merge_found}Use version control as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does: " \
                "merge the pull request of intent %{intent_id} into the intent's base, " \
                "and leave it open only when the owner asked. " \
                "Then add the line '- Merged: <branch> into <base> at <commit or pull request>' under ## Verification " \
                "in %{intent_folder}/outcome.md, then run plastic sync up. Plastic runs no version control command; it records what you write."
            step "confirm the architecture map", done: ->(context) { context.map_recorded },
              say: "Now that the work is delivered, fetch the architecture map once more, with the tool you used before planning " \
                "or by mapping the code yourself, and confirm that it describes the delivered code. Then add the line " \
                "'- Architecture map: <tool> at <source revision>' under ## Verification in %{intent_folder}/outcome.md. " \
                "Run plastic sync up and then plastic intent end %{intent_id} again."

            outcome :handoff, stops: :failure, offers: "plastic intent end %{intent_id}",
              because: "the agent merges the code and confirms the architecture map and records both in outcome.md"
            outcome :done, offers: nil, because: "the merge and the architecture map are recorded"
          end
        end
      end
    end
  end
end
