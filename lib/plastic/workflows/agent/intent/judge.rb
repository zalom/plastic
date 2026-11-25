# frozen_string_literal: true

require_relative "../../../agent_workflow"
require_relative "../../../graph/work/completion/review"

module Plastic
  module Workflows
    module Agent
      module Intent
        # The agent reads the spec and the findings of every node, decides, and records the verdict.
        class Judge < AgentWorkflow
          summary "Has the agent read the spec and the findings, decide and record the verdict."
          step "judge the delivery", done: ->(context) { Plastic::Graph::Work::Completion::Review.of(context).counting? },
            say: "Start a reasoning judge agent; the harness picks which kind. Tell it to read spec.md and the findings of every node, " \
              "check each done criterion against the delivered work and decide: accept when every criterion holds, " \
              "revise when something falls short. It records the verdict with " \
              "plastic intent verdict %{intent_id} accept|revise TEXT. " \
              "A revise starts a second review round, and a second revise stops the intent for the owner, who can grant one more round with plastic intent grant or hand the last gap to a follow-up intent with plastic intent handover."

          outcome :handoff, offers: "plastic intent verdict %{intent_id} accept|revise TEXT",
            because: "the agent judges the delivery and records the verdict"
          outcome :done, offers: nil, because: "the delivery is judged"
        end
      end
    end
  end
end
