# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/agent/intent/discover"

class WorkflowAgentIntentDiscoverTest < Plastic::TestCase
  def test_defines_a_kernel_agent_handoff_and_quotes_the_external_commands
    context = Plastic::Context.new(declared: %i[handoff_text context_command context_complete], facts: { handoff_text: "Submit the selected context.", context_command: "plastic intent context 1 --from FILE", context_complete: false }, graphs: {})

    handoff = Plastic::Workflows::Agent::Intent::Discover.call(context)
    commands = Plastic::Workflows::Agent::Intent::Discover.retrieval_handoff(intent_id: "1", project: "global", search: Plastic::Workflows::Agent::Intent::Discover.search_command("quoted terms; keep literal", ["global", "other store"]))

    assert_equal ["Submit the selected context."], handoff.steps
    assert_equal "plastic search quoted\\ terms\\;\\ keep\\ literal --source-project global --source-project other\\ store", commands.fetch("search")
    assert_equal "plastic intent context 1 --from FILE --project global", commands.fetch("context")
  end
end
