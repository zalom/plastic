# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_claim"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_remove"
require_relative "../../../scripts/lib/plastic/commands/node_done"
require_relative "../../../scripts/lib/plastic/commands/node_ask"
require_relative "../../../scripts/lib/plastic/commands/node_fail"
require_relative "../../../scripts/lib/plastic/commands/node_release"
require_relative "../../../scripts/lib/plastic/commands/edge_add"

class NodeClaimTest < Plastic::TestCase
  def test_the_claim_offers_the_text_and_no_judge
    open_intent
    add_node("a")

    out = claim("n1").out

    assert_includes out, "plastic node done 1 n1 TEXT"
    refute_includes out, "--judge"
  end

  def add_node(title)
    write("store/1--alpha/spec.md", "# Spec\n\n## Done criteria\n- [done] Done\n")
    sync_up
    plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)
  end

  def two_linked_nodes
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)
  end

  def claim(*args) = plastic("node", "claim", "1", *args, table: Plastic::CLI::TABLE)

  def test_the_brief_includes_the_last_reason
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "fail", "1", "n1", "boom", table: Plastic::CLI::TABLE)
    plastic("node", "release", "1", "n1", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_includes result.out, "last reason: boom"
    assert_equal 0, result.code
    assert_equal "", result.err
  end

  def fail_and_release
    claim("n1")
    plastic("node", "fail", "1", "n1", "boom", table: Plastic::CLI::TABLE)
    plastic("node", "release", "1", "n1", table: Plastic::CLI::TABLE)
  end

  def test_the_fourth_claim_moves_the_node_to_needs_info_and_keeps_its_findings
    open_intent
    add_node("a")
    3.times { fail_and_release }

    result = claim("n1")

    assert_equal 3, result.code
    node = store_graphs.retrieval.node("1", "n1")

    assert_equal "needs_info", node.state
    assert_equal "boom", node.reason
  end

  def test_claiming_a_node_that_needs_an_open_node_is_refused
    two_linked_nodes

    result = claim("n2")

    assert_equal 1, result.code
    assert_includes result.err, "node n2 needs a node that is not done"
    assert_equal "", result.out
  end

  def test_a_node_refused_for_its_needs_is_claimed_once_they_are_done
    two_linked_nodes
    claim("n2")
    claim("n1")
    plastic("node", "done", "1", "n1", "ok", table: Plastic::CLI::TABLE)

    result = claim("n2")

    assert_call result, code: 0, out: ["because: node n2 is claimed\n"]
    assert_equal "claimed", store_graphs.retrieval.node("1", "n2").state
  end

  def test_a_refused_claim_is_refused_again_on_the_next_call
    open_intent
    claim("n9")

    result = claim("n9")

    assert_equal 1, result.code
    assert_includes result.err, "no node n9 in intent 1"
  end

  def test_the_brief_names_the_input_file
    open_intent
    write("store/1--alpha/spec.md", "# Spec\n\n## Done criteria\n- [done] Done\n")
    sync_up
    plastic("node", "add", "1", "a", "--criterion", "done", "--input", "docs/a.md", table: Plastic::CLI::TABLE)

    call = claim("n1")

    assert_equal [0, ""], [call.code, call.err]
    assert_includes call.out, "input: docs/a.md"
  end
end
