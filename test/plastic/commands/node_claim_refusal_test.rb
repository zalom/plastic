# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_claim"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_remove"
require_relative "../../../scripts/lib/plastic/commands/node_done"
require_relative "../../../scripts/lib/plastic/commands/node_ask"
require_relative "../../../scripts/lib/plastic/commands/node_fail"

class NodeClaimRefusalTest < Plastic::TestCase
  def claim(*args) = plastic("node", "claim", "1", *args, table: Plastic::CLI::TABLE)

  def add_node(title)
    write("store/1--alpha/spec.md", "# Spec\n\n## Done criteria\n- [done] Done\n")
    sync_up
    plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)
  end

  def test_claiming_a_done_node_is_refused
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "done", "1", "n1", "ok", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 1, result.code
    assert_equal RUN_ROW, result.out
    assert_equal "plastic: node n1 is done; it cannot move to claimed\n", result.err
  end

  def test_claiming_a_needs_info_node_is_refused
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "ask", "1", "n1", "which way?", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 1, result.code
    assert_equal RUN_ROW, result.out
    assert_equal "plastic: node n1 is needs_info; it cannot move to claimed\n", result.err
  end

  def test_claiming_a_removed_node_is_refused
    open_intent
    add_node("a")
    plastic("node", "remove", "1", "n1", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 1, result.code
    assert_equal RUN_ROW, result.out
    assert_equal "plastic: node n1 is removed; it cannot move to claimed\n", result.err
  end

  def test_claiming_an_already_claimed_node_is_refused
    open_intent
    add_node("a")
    claim("n1")

    result = claim("n1")

    assert_equal 1, result.code
  end
end
