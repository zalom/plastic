# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_remove"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_claim"

class NodeRemoveTest < Plastic::TestCase
  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def remove(*args) = plastic("node", "remove", *args, table: Plastic::CLI::TABLE)

  def test_removing_a_claimed_node_exits_1
    open_intent
    add_node("a")
    plastic("node", "claim", "1", "n1", table: Plastic::CLI::TABLE)

    result = remove("1", "n1")

    assert_equal 1, result.code
    assert_equal "", result.out
    assert_equal "plastic: code_remove_node, gate: node n1 is claimed; it cannot move to removed\n", result.err
  end

  def test_removing_an_open_node_moves_it_to_removed
    open_intent
    add_node("a")

    result = remove("1", "n1", "--reason", "not needed")

    assert_equal 0, result.code
    assert_equal "removed", store_graphs.retrieval.node("1", "n1").state
  end

  def test_preview_matches_apply_on_an_identical_home
    twin = twin_run("node", "remove", "1", "n1") do |home|
      seed_intents(home, "Alpha")
      seed_nodes(home, "a", "b")
      call_in(home, "edge", "add", "1", "n1", "n2")
    end

    assert_preview_matches_apply(twin)
    assert_equal 0, twin.previewed.code
  end

  def test_a_preview_of_a_missing_node_refuses_like_the_apply
    twin = twin_run("node", "remove", "1", "n9") do |home|
      seed_intents(home, "Alpha")
      seed_nodes(home, "a")
    end

    assert_preview_matches_apply(twin)
    refute_equal 0, twin.previewed.code
    assert_includes twin.previewed.err, "n9"
  end
end
