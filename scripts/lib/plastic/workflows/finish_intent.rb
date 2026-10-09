# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The harness writes the records the close needs and has the work judged.
    class FinishIntent < AgentWorkflow
      step "finish the required records", done: ->(context) { context.requirements.empty? },
        say: "Complete these recorded prerequisites: %{requirements}"
      step "have the delivery judged", done: ->(context) { context.judged },
        say: "No accepted review counts yet. Run plastic intent judge %{intent_id}; the judge records the verdict of the next review round with plastic intent verdict. " \
          "Then run plastic intent end %{intent_id} again."

      outcome :handoff, offers: nil, because: "intent %{intent_id} cannot end yet. %{missing}"
      outcome :done, offers: nil, because: "the completion records are ready"
    end
  end
end
