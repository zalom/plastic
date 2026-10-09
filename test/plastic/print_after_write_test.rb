# frozen_string_literal: true

require_relative "../test_helper"

class PrintAfterWriteTest < Plastic::TestCase
  include LifecycleHelper

  def run_cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def prints = Plastic::Graph::Prints.of_store(store_graphs.retrieval)

  def print_at(path) = prints.find { |print| print.path == path }

  def stale?(path) = File.read(store_path(path)) != print_at(path).text

  def stale_paths(only = nil)
    paths = prints.map(&:path)
    paths = paths.select { |path| path.start_with?(only) } if only
    paths.select { |path| !File.exist?(store_path(path)) || stale?(path) }
  end

  def assert_files_level(only = nil) = assert_empty(stale_paths(only))

  def keyed
    intent = open_keyed_intent
    run_cli("node", "add", "1", "first", "--criterion", "done")
    intent
  end

  def test_node_add_prints_the_graph_without_graph_show
    intent = open_keyed_intent
    run_cli("node", "add", "1", "first", "--criterion", "done")

    assert_files_level
    assert_equal 1, JSON.parse(File.read(store_path("#{intent.dir}/graph.json"))).fetch("nodes").size
  end

  def test_edge_add_prints_the_edge
    intent = keyed
    run_cli("node", "add", "1", "second", "--criterion", "done")
    run_cli("edge", "add", "1", "n1", "n2")

    assert_files_level
    assert_equal 1, JSON.parse(File.read(store_path("#{intent.dir}/graph.json"))).fetch("edges").size
  end

  def test_node_done_prints_the_state
    keyed
    run_cli("intent", "approve", "1")
    run_cli("auto", "1")
    run_cli("node", "claim", "1", "n1")
    run_cli("node", "done", "1", "n1", "it passes")

    assert_files_level
  end

  def test_intent_rule_prints_the_files
    open_keyed_intent
    run_cli("intent", "rule", "1", "Flowbite styles every delivery")

    assert_files_level
  end

  def test_intent_link_prints_the_files
    open_keyed_intent
    open_intent("Beta")
    run_cli("intent", "link", "1", "cites", "2")

    assert_files_level
  end

  def test_intent_revise_prints_the_files
    open_keyed_intent
    result = run_cli("intent", "revise", "1", "Alpha, after grilling", "--why", "The goal moved")

    assert_equal 0, result.code, result.err
    assert_files_level
  end

  def test_intent_new_prints_the_folder_it_made
    result = run_cli("intent", "new", "Fresh")

    assert_equal 0, result.code
    assert_files_level
    assert_path_exists store_path("store/1--fresh/graph.json")
  end

  def roadmap_with_two_items
    run_cli("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d")
    run_cli("roadmap", "add", "r1", "1", "a", "--title", "A", "--goal", "Item goal", "--done", "item done")
    run_cli("roadmap", "add", "r1", "1", "b", "--title", "B")
  end

  def test_roadmap_adds_and_logs_print_the_roadmap_file
    roadmap_with_two_items
    run_cli("roadmap", "log", "r1", "a", "a log line")

    assert_files_level("roadmaps/")
    assert_includes File.read(store_path("roadmaps/r1.md")), "A"
  end

  def test_roadmap_drop_and_start_print_the_roadmap_file_and_the_intent
    roadmap_with_two_items
    run_cli("roadmap", "drop", "r1", "b")
    run_cli("roadmap", "start", "r1", "a")

    assert_files_level("roadmaps/")
    assert_path_exists store_path("store/1--a/graph.json")
  end

  def test_a_refused_write_leaves_a_hand_edited_graph_json_alone
    intent = open_keyed_intent
    File.write(store_path("#{intent.dir}/graph.json"), '{"hand":true}')
    result = run_cli("node", "add", "1", "first", "--criterion", "nope")

    assert_equal 1, result.code
    assert_equal '{"hand":true}', File.read(store_path("#{intent.dir}/graph.json"))
  end

  def test_a_print_that_cannot_write_ends_the_call_in_exit_1
    intent = open_keyed_intent
    FileUtils.rm_f(store_path("#{intent.dir}/graph.json"))
    FileUtils.mkdir_p(store_path("#{intent.dir}/graph.json"))
    result = run_cli("node", "add", "1", "first", "--criterion", "done")

    assert_equal 1, result.code
    refute_empty result.err
  end
end
