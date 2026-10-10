# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/edge_remove"
require_relative "../../../scripts/lib/plastic/commands/edge_add"
require_relative "../../../scripts/lib/plastic/commands/node_add"

class EdgeRemoveTest < Plastic::TestCase
  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def test_a_missing_edge_exits_1
    open_keyed_intent
    add_node("a")
    add_node("b")

    result = plastic("edge", "remove", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    assert_equal RUN_ROW, result.out
    assert_equal "plastic: code_remove_edge, gate: no edge n1 to n2 in intent 1\n", result.err
  end

  def test_retry_after_adding_the_missing_edge_succeeds
    open_keyed_intent
    add_node("a")
    add_node("b")
    failed = plastic("edge", "remove", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    assert_call failed, code: 1, out: RUN_ROW, err: ["no edge n1 to n2 in intent 1"]
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = plastic("edge", "remove", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: ["edge: n1 to n2 removed"]
    assert_empty store_graphs.retrieval.edges("1")
  end

  def test_removing_an_existing_edge_succeeds
    open_keyed_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = plastic("edge", "remove", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    assert_call result, code: 0,
      out: "edge: n1 to n2 removed\nwrote:  1 routine run in local.db\n        1 edge in work_graph.db\nfiles:  store/1--alpha/graph.json\n\nnext: plastic graph show 1 --project global\nbecause: edge n1 to n2 is gone\n"
    assert_empty store_graphs.databases.fetch(:work).rows("SELECT * FROM edges")
  end

  def test_preview_matches_apply_on_an_identical_home
    twin = twin_run("edge", "remove", "1", "n1", "n2") do |home|
      seed_intents(home, "Alpha")
      seed_nodes(home, "a", "b", "c")
      call_in(home, "edge", "add", "1", "n1", "n2")
      call_in(home, "edge", "add", "1", "n2", "n3")
    end

    assert_preview_matches_apply(twin)
    assert_equal 0, twin.previewed.code
  end
end
