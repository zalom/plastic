# frozen_string_literal: true

require_relative "../../test_helper"

class NodeDoneTest < Plastic::TestCase
  include LifecycleHelper

  USAGE = "plastic node done ID NODE --findings TEXT [--repair]\n"

  def setup
    super
    specified
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "claim", "1", "n1")
  end

  def test_finishing_a_claimed_node_offers_the_ready_set
    result = cli("node", "done", "1", "n1", "--findings", "ok")

    assert_call result, code: 0, out: "node: n1 done\nwrote:  1 node in work_graph.db\n\nnext: plastic graph ready 1 --project global\nbecause: node n1 is done\n"
  end

  def test_the_usage_line_has_findings_only
    assert_equal USAGE.chomp, Plastic::Commands::NodeDone.usage_line("node done")
  end

  def test_the_judge_option_is_a_usage_error_and_the_node_stays_claimed
    result = cli("node", "done", "1", "n1", "--judge", "tests", "--findings", "ok")

    assert_equal 2, result.code
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_empty_findings_exit_2_and_leave_the_node_claimed
    result = cli("node", "done", "1", "n1", "--findings", "")

    assert_call result, code: 2, err: /findings/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_blank_findings_exit_2_and_leave_the_node_claimed
    result = cli("node", "done", "1", "n1", "--findings", " ")

    assert_call result, code: 2, err: /findings/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_missing_findings_exit_2_and_leave_the_node_claimed
    result = cli("node", "done", "1", "n1")

    assert_call result, code: 2, err: /findings/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_repair_replaces_the_findings_of_a_done_node
    cli("node", "done", "1", "n1", "--findings", "first")

    result = cli("node", "done", "1", "n1", "--repair", "--findings", "Rechecked the target")

    assert_call result, code: 0, out: ["node: n1 done"]
    assert_equal ["done", "Rechecked the target"], retrieval.node("1", "n1").to_h.values_at(:state, :findings)
  end
end
