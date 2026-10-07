# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/work/delivery_action"

class WorkDeliveryActionTest < Plastic::TestCase
  def setup
    super
    @work = store_graphs.work
    @work.write_intent(title: "Alpha")
  end

  def action(intent_id = "1") = Plastic::Graph::Work::DeliveryAction.new(retrieval, intent_id).call

  def plan(*titles) = titles.each { |title| @work.add_node(intent_id: "1", title:) }

  def claim(id) = @work.claim_node(intent_id: "1", id:, by: "worker")

  def test_an_intent_with_no_live_node_asks_the_harness_to_plan
    plan("Gone")
    @work.remove_node(intent_id: "1", id: "n1")
    command, reason, instructions = action

    assert_equal [nil, "the harness must plan this intent"], [command, reason]
    assert_includes instructions, "plastic node add 1 TITLE --criterion TEXT"
  end

def test_the_planning_instruction_starts_with_fetching_the_architecture_map
  instructions = action.last

  assert instructions.start_with?("Before you plan, fetch the architecture map as current as possible with an architecture mapping tool such as Enola, or map the code yourself; Plastic runs no tool. Read the intent's goal")
  assert_includes instructions, "such as Enola"
  assert_includes instructions, "map the code yourself"
  assert_includes instructions, "Plastic runs no tool"
end

  def test_a_ready_node_is_claimed
    plan("Build")

    assert_equal ["plastic node claim 1 n1", "node n1 is ready", nil], action
  end

  def test_a_failed_node_is_released_before_anything_else
    plan("Build", "Test")
    claim("n1")
    @work.fail_node(intent_id: "1", id: "n1", reason: "red")

    assert_equal ["plastic node release 1 n1", "node n1 failed; release it before retrying", nil], action
  end

  def test_a_parked_node_asks_the_owner_its_question
    plan("Build")
    claim("n1")
    @work.park_node(intent_id: "1", id: "n1", question: "Which store?")

    assert_equal [nil, "the owner must answer node n1"], action.first(2)
    assert_includes action.last, "Ask the owner: Which store?."
    refute_includes action.last, "architecture map"
  end

  def test_a_claimed_node_names_its_worker
    plan("Build")
    claim("n1")

    assert_equal [nil, "node n1 is already claimed"], action.first(2)
    assert_includes action.last, "with its worker worker"
    refute_includes action.last, "architecture map"
  end

  def test_a_claimed_node_with_no_worker_name_never_prints_an_empty_name
    plan("Build")
    @work.claim_node(intent_id: "1", id: "n1", by: nil)
    instructions = action.last

    refute_includes instructions, "worker ."
    assert_includes instructions, "Continue node n1. Record the result"
  end

  def test_nodes_waiting_on_a_claimed_node_report_the_claim
    plan("Build", "Test")
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")
    claim("n1")

    assert_equal "node n1 is already claimed", action[1]
  end

  def test_a_node_needing_a_removed_node_asks_for_the_dependencies_to_be_repaired
    plan("Build", "Test")
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")
    @work.remove_node(intent_id: "1", id: "n1")

    assert_equal [nil, "dependencies block the remaining nodes"], action.first(2)
    refute_includes action.last, "architecture map"
  end

  def test_all_nodes_done_points_to_the_intent_end
    plan("Build")
    claim("n1")
    @work.done_node(intent_id: "1", id: "n1", judge: "tests", findings: "green")

    assert_equal ["plastic intent end 1", "the nodes are done; verify the intent's criteria", nil], action
  end

  def test_a_closed_intent_has_no_action
    @work.write_intent(title: "Beta", status: "done")

    assert_equal ["none", "intent 2 is closed", nil], action("2")
  end
end
