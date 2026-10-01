# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_claim"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_remove"
require_relative "../../../scripts/lib/plastic/commands/node_done"
require_relative "../../../scripts/lib/plastic/commands/node_park"
require_relative "../../../scripts/lib/plastic/commands/node_fail"
require_relative "../../../scripts/lib/plastic/commands/node_release"

class NodeClaimTest < Plastic::TestCase
  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def claim(*args) = plastic("node", "claim", "1", *args, table: Plastic::CLI::TABLE)

  def test_claiming_a_done_node_is_refused
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "done", "1", "n1", "--judge", "tests", "--findings", "ok", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 3, result.code
  end

  def test_claiming_a_parked_node_is_refused
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "park", "1", "n1", "--question", "which way?", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 3, result.code
  end

  def test_claiming_a_removed_node_is_refused
    open_intent
    add_node("a")
    plastic("node", "remove", "1", "n1", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 3, result.code
  end

  def test_claiming_an_already_claimed_node_is_refused
    open_intent
    add_node("a")
    claim("n1")

    result = claim("n1")

    assert_equal 3, result.code
  end

  def test_the_brief_includes_the_last_findings
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "fail", "1", "n1", "--reason", "boom", table: Plastic::CLI::TABLE)
    plastic("node", "release", "1", "n1", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_includes result.out, "last reason: boom"
  end

  def fail_and_release
    claim("n1")
    plastic("node", "fail", "1", "n1", "--reason", "boom", table: Plastic::CLI::TABLE)
    plastic("node", "release", "1", "n1", table: Plastic::CLI::TABLE)
  end

  def test_the_fourth_claim_parks_the_node_and_keeps_its_findings
    open_intent
    add_node("a")
    3.times { fail_and_release }

    result = claim("n1")

    assert_equal 3, result.code
    node = store_graphs.retrieval.node("1", "n1")

    assert_equal "parked", node.state
    assert_equal "boom", node.reason
  end
end
