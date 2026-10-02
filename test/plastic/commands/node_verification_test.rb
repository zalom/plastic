# frozen_string_literal: true

require_relative "../../test_helper"

class NodeVerificationTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def claimed_node
    open_intent
    cli("node", "add", "1", "Build", "--criterion", "Ships")
    cli("node", "claim", "1", "n1")
  end

  def test_empty_findings_leave_the_node_claimed
    claimed_node

    result = cli("node", "done", "1", "n1", "--judge", "agent", "--findings", " ")

    assert_equal 2, result.code
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_missing_findings_leave_the_node_claimed
    claimed_node

    result = cli("node", "done", "1", "n1", "--judge", "agent")

    assert_equal 2, result.code
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_explicit_repair_records_verification_for_an_existing_done_node
    claimed_node
    store_graphs.work.done_node(intent_id: "1", id: "n1")

    result = cli("node", "done", "1", "n1", "--repair", "--judge", "tool", "--findings", "Rechecked the target")

    assert_equal 0, result.code
    assert_equal ["done", "tool", "Rechecked the target", 1], retrieval.node("1", "n1").to_h.values_at(:state, :judge, :findings, :retries)
  end
end
