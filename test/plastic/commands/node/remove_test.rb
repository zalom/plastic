# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/remove"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/node/claim"

class NodeRemoveCaseTest < Plastic::TestCase
  def test_removing_a_node_prints_it_and_offers_the_ready_list
    alpha_with_node(approved: false)

    assert_case line('node remove 1 n1 --reason "merged into Test"'), code: 0, out: ["node: n1 removed", "next: plastic graph ready 1"]
  end

  def test_removing_a_node_that_does_not_exist_exits_1_and_names_it
    alpha_with_node(approved: false)

    assert_case line("node remove 1 n9"), code: 1, out: "", err: ["no node n9 in intent 1"]
  end

  def test_removing_in_a_missing_intent_exits_1_and_names_it
    assert_case line("node remove 9 n1"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class NodeRemoveTest < Plastic::TestCase
  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

  def remove(*args) = plastic("node", "remove", *args, table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

  def test_removing_a_claimed_node_exits_1
    open_keyed_intent
    add_node("a")
    plastic("node", "claim", "1", "n1", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

    result = remove("1", "n1")

    assert_equal 1, result.code
    assert_empty result.out
    assert_equal "plastic: node n1 is claimed; it cannot move to removed\n", result.err
  end

  def test_removing_an_open_node_moves_it_to_removed
    open_keyed_intent
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
