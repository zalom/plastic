# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/check_architecture"

class CheckArchitectureTest < Plastic::TestCase
  def test_the_check_is_always_handed_to_the_agent
    handoff, = run_workflow(Plastic::Workflows::CheckArchitecture)

    assert_equal ["plastic architecture refresh", "the agent judges whether the architecture map is current"],
      [handoff.next_command, handoff.because]
  end

  def test_the_handoff_leaves_the_choice_of_tool_to_the_agent
    handoff, = run_workflow(Plastic::Workflows::CheckArchitecture)

    assert_includes sole(handoff.steps), "the choice of tool is yours"
  end
end
