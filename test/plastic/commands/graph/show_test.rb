# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/show"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/edge/add"

class GraphShowCaseTest < Plastic::TestCase
  def test_the_graph_after_a_full_pass_shows_the_done_node_the_open_node_and_the_edge
    work_graph_pass

    assert_case line("graph show 1"), code: 0, out: ["node: n1 done do the thing", "node: n2 open build it", "edge: n1 to n2"]
  end

  def test_an_intent_with_no_nodes_shows_nothing_and_offers_the_ready_list
    ran("intent new Alpha")

    assert_case line("graph show 1"), code: 0, out: ["next: plastic graph ready 1"]
  end

  def test_a_missing_intent_exits_1_and_names_it
    assert_case line("graph show 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class GraphShowTest < Plastic::TestCase
  def call(*args) = plastic("graph", "show", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def graph_path(intent) = store_path("#{intent.dir}/graph.json")

  def test_prints_each_node_and_edge
    open_keyed_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = call("1")

    assert_call result, code: 0, out: ["node: n1 open a", "node: n2 open b", "edge: n1 to n2", "next: plastic graph ready 1"], err: ""
  end

  def test_prints_each_input_path_of_a_node_on_its_own_line_under_the_node
    open_keyed_intent
    plastic("node", "add", "1", "a", "--criterion", "done", "--input", "docs/a.md", "--input", "docs/b.md", table: Plastic::CLI::TABLE)
    add_node("b")

    assert_call call("1"), code: 0, out: ["node: n1 open a", "input: docs/a.md", "input: docs/b.md", "node: n2 open b", "next: plastic graph ready 1"], err: ""
  end

  def test_a_hand_edited_graph_json_survives_the_call_and_no_row_is_added
    intent = open_keyed_intent
    add_node("a")
    File.write(graph_path(intent), '{"bogus":true}')
    before = run_count

    result = call("1")

    assert_equal '{"bogus":true}', File.read(graph_path(intent))
    assert_equal before, run_count
    assert_equal "", result.out.lines.grep(/^wrote:/).join
  end

  def run_count = store_graphs.databases.fetch(:local).row("SELECT count(*) AS n FROM command_runs").fetch("n")
end
