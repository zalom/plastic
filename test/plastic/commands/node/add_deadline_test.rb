# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/graph/show"

# `node add --deadline MINUTES` stores how long a claim on the node may run before `graph ready` reports it.
class NodeAddDeadlineTest < Plastic::TestCase
  def setup
    super
    alpha_specified
  end

  def deadlines = store_graphs.retrieval.structure.nodes("1").map(&:deadline)

  def test_a_node_added_with_a_deadline_prints_the_node_and_stores_the_minutes
    assert_case line("node add 1 Build --criterion tests-pass --deadline 30"), code: 0, out: ["node: n1"]
    assert_equal [30], deadlines
  end

  def test_a_node_added_without_a_deadline_stores_none
    ran("node add 1 Build --criterion tests-pass")

    assert_equal [nil], deadlines
  end

  def test_graph_show_prints_the_deadline_on_the_node_line
    ran("node add 1 Build --criterion tests-pass --deadline 30")

    assert_case line("graph show 1"), code: 0, out: ["node: n1 open Build, deadline 30 minutes"]
  end

  def test_graph_show_prints_no_deadline_for_a_node_without_one
    ran("node add 1 Build --criterion tests-pass")

    refute_includes line("graph show 1").out, "deadline"
  end

  def test_the_graph_file_carries_the_deadline_of_each_node
    ran("node add 1 Build --criterion tests-pass --deadline 30", "node add 1 Test --criterion tests-pass")

    nodes = JSON.parse(File.read(store_path("store/1--alpha/graph.json"))).fetch("nodes")

    assert_equal [["n1", 30], ["n2", nil]], nodes.map { |node| node.values_at("id", "deadline") }
  end

  %w[0 -5 abc 1.5 30m].each do |value|
    define_method("test_a_deadline_of_#{value.tr("-.", "_")}_exits_2_names_the_switch_and_adds_no_node") do
      result = line("node add 1 Build --criterion tests-pass --deadline #{value}")

      assert_equal [2, ""], [result.code, result.out]
      assert_includes result.err, "--deadline takes a whole number of minutes above 0"
      assert_empty deadlines
    end
  end
end
