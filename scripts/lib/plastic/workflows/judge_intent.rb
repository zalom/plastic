# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The agent reads the spec and the findings of every node, decides, and records the verdict.
    class JudgeIntent < AgentWorkflow
      step "judge the delivery", done: ->(context) { context.retrieval.verdicts(context.intent_id).any? { |round| round.verdict == "accept" } },
        say: "Start a reasoning judge agent; the harness picks which kind. Tell it to read spec.md and the findings of every node, " \
          "check each done criterion against the delivered work and decide: accept when every criterion holds, " \
          "revise when something falls short. It records the verdict with " \
          "plastic intent verdict %{intent_id} accept|revise TEXT. " \
          "A revise starts a second review round, and a second revise stops the intent for the owner."

      outcome :handoff, offers: "plastic intent verdict %{intent_id} accept|revise TEXT",
        because: "the agent judges the delivery and records the verdict"
      outcome :done, offers: nil, because: "the delivery is judged"
    end
  end
end
