# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The agent reads the spec and the findings of every node, decides, and records the verdict.
    class JudgeIntent < AgentWorkflow
      step "judge the delivery", done: ->(context) { context.retrieval.verdicts(context.intent_id).any? { |round| round.verdict == "accept" } },
        say: "Read spec.md and the findings of every node. Check each done criterion against the delivered work and decide: " \
          "accept when every criterion holds, revise when something falls short. Record it with " \
          "plastic intent judge %{intent_id} --verdict accept|revise --findings TEXT. " \
          "A revise starts a second review round, and a second revise stops the intent for the owner."

      outcome :handoff, offers: "plastic intent judge %{intent_id} --verdict accept|revise --findings TEXT",
        because: "the agent judges the delivery and records the verdict"
      outcome :done, offers: nil, because: "the delivery is judged"
    end
  end
end
