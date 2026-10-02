# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_claim"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_remove"
require_relative "../../../scripts/lib/plastic/commands/node_done"
require_relative "../../../scripts/lib/plastic/commands/node_park"
require_relative "../../../scripts/lib/plastic/commands/node_fail"
require_relative "../../../scripts/lib/plastic/commands/node_release"
require_relative "../../../scripts/lib/plastic/commands/edge_add"

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

  def test_the_brief_includes_the_last_reason
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

  def test_claiming_a_node_that_needs_an_open_node_is_refused
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = claim("n2")

    assert_equal 3, result.code
    assert_includes result.err, "node n2 needs a node that is not done"
  end

  def test_a_node_refused_for_its_needs_is_claimed_once_they_are_done
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)
    claim("n2")
    claim("n1")
    plastic("node", "done", "1", "n1", "--judge", "tests", "--findings", "ok", table: Plastic::CLI::TABLE)

    result = claim("n2")

    assert_equal 0, result.code
    assert_equal "claimed", store_graphs.retrieval.node("1", "n2").state
  end

  def test_a_refused_claim_is_refused_again_on_the_next_call
    open_intent
    claim("n9")

    result = claim("n9")

    assert_equal 3, result.code
    assert_includes result.err, "no node n9 in intent 1"
  end

  def test_the_brief_names_the_input_file
    open_intent
    plastic("node", "add", "1", "a", "--criterion", "done", "--input", "docs/a.md", table: Plastic::CLI::TABLE)

    assert_includes claim("n1").out, "input: docs/a.md"
  end
end
