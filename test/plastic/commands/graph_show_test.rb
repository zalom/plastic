# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/graph_show"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/edge_add"

class GraphShowTest < Plastic::TestCase
  def call(*args) = plastic("graph", "show", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def graph_path(intent) = store_path("#{intent.dir}/graph.json")

  def test_prints_each_node_and_edge
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = call("1")

    assert_call result, code: 0, out: ["node: n1 open a", "edge: n1 to n2"]
  end

  def test_a_hand_edited_graph_json_is_overwritten_from_rows
    intent = open_intent
    add_node("a")
    File.write(graph_path(intent), '{"bogus":true}')

    call("1")

    written = JSON.parse(File.read(graph_path(intent)))

    refute written.key?("bogus")
    assert_equal 1, written.fetch("nodes").size
  end

  def test_a_preview_leaves_graph_json_as_it_was
    twin = twin_run("graph", "show", "1") do |home|
      seed_intents(home, "Alpha")
      seed_nodes(home, "a")
      File.write(File.join(home, "stores", "global", "store", "1--alpha", "graph.json"), '{"bogus":true}')
    end
    store = File.join(twin.first, "stores", "global")

    assert_equal "{\"bogus\":true}", File.read(File.join(store, "store", "1--alpha", "graph.json"))
    assert_equal [], twin.changed_paths
    assert_equal ["change #{store}/.gitignore", "change #{store}/store/1--alpha/1--alpha.md", "change #{store}/store/1--alpha/graph.json",
      "change #{store}/store/1--alpha/savepoint.md", "change #{store}/store/index.json"], twin.preview_paths.sort
  end

  def test_preview_matches_apply_on_an_identical_home
    twin = twin_run("graph", "show", "1") do |home|
      seed_intents(home, "Alpha")
      seed_nodes(home, "a", "b")
      call_in(home, "edge", "add", "1", "n1", "n2")
    end

    assert_preview_matches_apply(twin)
    assert_includes twin.previewed_lines, "node: n1 open a"
    assert_includes twin.previewed_lines, "edge: n1 to n2"
  end

  def test_a_preview_with_a_linked_intent_folder_refuses_and_the_outside_folder_is_untouched
    with_home do |home|
      seed_intents(home, "Alpha")
      outside = File.join(File.dirname(home), "outside")
      FileUtils.mv(File.join(home, "stores", "global", "store", "1--alpha"), outside)
      File.symlink(outside, File.join(home, "stores", "global", "store", "1--alpha"))
      before = [snapshot(home), snapshot(outside)]

      result = call_in(home, "graph", "show", "1", "--dry-run")

      assert_equal 3, result.code
      assert_includes result.err, File.join(home, "stores", "global", "store", "1--alpha")
      assert_equal before, [snapshot(home), snapshot(outside)]
    end
  end
end
