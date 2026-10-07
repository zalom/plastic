# frozen_string_literal: true

require_relative "../agent_workflow"

module Plastic
  module Workflows
    # The harness verifies each criterion and writes the outcome before attesting.
    class FinishIntent < AgentWorkflow
      step "finish the required records", done: ->(context) { context.requirements.empty? },
        say: "Complete these recorded prerequisites: %{requirements}"
      step "confirm the architecture map", done: ->(context) { !context.attestation.nil? },
        say: "Now that the work is delivered, fetch the architecture map once more, with the tool you used before planning " \
          "or by mapping the code yourself, and confirm that it describes the delivered code. Note the tool and the " \
          "source revision the map describes under Verification in outcome.md."
      step "record the acceptance evidence", done: ->(context) { !context.attestation.nil? },
        say: "Verify every done criterion. Write completion.json inside %{intent_folder}, using this JSON shape:\n%{evidence_example}\n" \
          "Replace each description with actual evidence. Write outcome.md there and run plastic sync up. " \
          "Then run plastic intent end %{intent_id} --judge tests|tool|agent|owner --evidence completion.json. " \
          "Choose the judge that actually accepted the intent. Use owner only for an explicit owner acceptance. " \
          "Plastic records this attestation; it does not run the checks itself."

      outcome :handoff, offers: nil, because: "the harness must verify the intent and record its outcome"
      outcome :done, offers: nil, because: "the completion records are ready"
    end
  end
end
