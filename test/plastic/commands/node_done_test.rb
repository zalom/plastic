# frozen_string_literal: true

require_relative "../../test_helper"

class NodeDoneTest < Plastic::TestCase
  USAGE = "plastic node done ID NODE [--judge WHO] --findings TEXT [--repair]\n"

  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def setup
    super
    open_intent
    cli("node", "add", "1", "Build", "--criterion", "Ships")
    cli("node", "claim", "1", "n1")
  end

  def test_finishing_a_claimed_node_offers_the_ready_set
    result = cli("node", "done", "1", "n1", "--judge", "tests", "--findings", "ok")

    assert_call result, code: 0, out: "node: n1 done\nwrote:  1 node in work_graph.db\n\nnext: plastic graph ready 1 --project global\nbecause: node n1 is done\n"
  end

  def test_a_bad_judge_exits_2
    result = cli("node", "done", "1", "n1", "--judge", "vibes", "--findings", "ok")

    assert_call result, code: 2, err: "plastic: --judge takes tests, tool, agent or owner\n#{USAGE}"
  end

  def test_empty_findings_exit_2_and_leave_the_node_claimed
    result = cli("node", "done", "1", "n1", "--judge", "agent", "--findings", " ")

    assert_call result, code: 2, err: /findings/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_missing_findings_exit_2_and_leave_the_node_claimed
    result = cli("node", "done", "1", "n1", "--judge", "agent")

    assert_call result, code: 2, err: /findings/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_explicit_repair_records_verification_for_an_existing_done_node
    store_graphs.work.done_node(intent_id: "1", id: "n1")

    result = cli("node", "done", "1", "n1", "--repair", "--judge", "tool", "--findings", "Rechecked the target")

    assert_call result, code: 0, out: ["node: n1 done"]
    assert_equal ["done", "tool", "Rechecked the target", 1],
      retrieval.node("1", "n1").to_h.values_at(:state, :judge, :findings, :retries)
  end
end
