# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/code_workflow"

class KeyTest < Minitest::Test
  def test_a_key_reads_apart_into_its_lane_and_its_class_name
    key = Plastic::Workflow::Key.parse(:code_close_intent)

    assert_equal ["code", "CloseIntent"], [key.lane, key.class_name]
  end

  def test_a_key_finds_its_workflow_class_in_the_namespace
    assert_equal Plastic::Workflows::MoveNode, Plastic::Workflow::Key.parse(:code_move_node).workflow_in(Plastic::Workflows)
  end

  def test_a_key_whose_lane_does_not_match_its_class_is_invalid
    error = assert_raises(Plastic::Invalid) { Plastic::Workflow::Key.parse(:agent_move_node).workflow_in(Plastic::Workflows) }

    assert_equal "agent_move_node names a agent workflow, and Plastic::Workflows::MoveNode is a code workflow", error.message
  end
end
