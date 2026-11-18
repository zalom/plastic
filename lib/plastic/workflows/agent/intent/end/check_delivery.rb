# frozen_string_literal: true

require_relative "../end"
require_relative "../../../../agent_workflow"

module Plastic
  module Workflows
    module Agent
      module Intent
        class End
          # The agent records how the work of the intent was delivered, by a merge, a direct commit or files
          # in the intent folder, and confirms the architecture map after code. Plastic runs no version
          # control command and records what the agent writes.
          class CheckDelivery < AgentWorkflow
            summary "Has the agent record how the work of the intent was delivered."
            step "record the delivery", done: ->(context) { context.delivery_recorded },
              say: "%{delivery_found}Record the delivery of intent %{intent_id} under ## Verification in %{intent_folder}/outcome.md with one line. " \
                "For code, use version control as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does: " \
                "merge the pull request of intent %{intent_id} into the intent's base, " \
                "and leave it open only when the owner asked. %{template_found}" \
                "Then add '- Merged: <branch> into <base> at <commit or pull request>', or '- Committed: <branch> at <commit>' " \
                "when the project commits straight to its branch. " \
                "Add '- Delivered: resources/output/<path> because <reason>' only for work that no version control holds: " \
                "put reports in %{intent_folder}/resources/output/reports and other files in %{intent_folder}/resources/output/files, " \
                "and name them in the line. Then run plastic sync up. Plastic runs no version control command; it records what you write."
            step "confirm the architecture map", done: ->(context) { context.map_recorded },
              say: "Now that the code is delivered, fetch the architecture map once more, with the tool you used before planning " \
                "or by mapping the code yourself, and confirm that it describes the delivered code. Then add the line " \
                "'- Architecture map: <tool> at <source revision>' under ## Verification in %{intent_folder}/outcome.md. " \
                "Run plastic sync up and then plastic intent end %{intent_id} again."

            outcome :handoff, stops: :failure, offers: "plastic intent end %{intent_id}",
              because: "the agent records the delivery, and the architecture map after code, in outcome.md"
            outcome :done, unreachable: true, offers: nil, because: "the delivery and the architecture map it needs are recorded"
          end
        end
      end
    end
  end
end
