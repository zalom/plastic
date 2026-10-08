# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The agent checks that the code is merged and confirms the architecture map,
    # then records both under Verification in outcome.md. Plastic runs no version
    # control command and records what the agent writes.
    class CheckMerge < AgentWorkflow
      step "check the code is merged", done: ->(context) { context.merge_recorded },
        say: "Check with your own version control tool that the intent's branch is merged into its base. " \
          "Then add the line `- Merged: <branch> into <base> at <commit or pull request>` under ## Verification " \
          "in %{intent_folder}/outcome.md. Plastic runs no version control command; it records what you write."
      step "confirm the architecture map", done: ->(context) { context.map_recorded },
        say: "Now that the work is delivered, fetch the architecture map once more, with the tool you used before planning " \
          "or by mapping the code yourself, and confirm that it describes the delivered code. Then add the line " \
          "`- Architecture map: <tool> at <source revision>` under ## Verification in %{intent_folder}/outcome.md. " \
          "Run plastic sync up and then plastic intent end %{intent_id} again."

      outcome :handoff, offers: nil, because: "the agent checks the merge and the architecture map and records both in outcome.md"
      outcome :done, offers: nil, because: "the merge and the architecture map are recorded"
    end
  end
end
