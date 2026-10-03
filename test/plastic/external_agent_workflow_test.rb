# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/plastic/external_agent_workflow"

class ExternalAgentWorkflowTest < Plastic::TestCase
  def test_defines_a_kernel_agent_handoff_and_quotes_the_external_commands
    context = Plastic::Context.new(declared: %i[handoff_text context_command context_complete], facts: { handoff_text: "Submit the selected context.", context_command: "plastic intent context 1 --from FILE", context_complete: false }, graphs: {})

    handoff = Plastic::ExternalAgentWorkflow.call(context)
    commands = Plastic::ExternalAgentWorkflow.retrieval_handoff(intent_id: "1", terms: "quoted terms; keep literal", sources: ["global", "other store"], project: "global")

    assert_equal ["Submit the selected context."], handoff.steps
    assert_equal "plastic search quoted\\ terms\\;\\ keep\\ literal --source-project global --source-project other\\ store", commands.fetch("search")
    assert_equal "plastic intent context 1 --from FILE --project global", commands.fetch("context")
  end
end
