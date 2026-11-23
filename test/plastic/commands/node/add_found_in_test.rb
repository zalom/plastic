# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/graph/show"
require_relative "../../../../lib/plastic/commands/graph/ready"
require_relative "../../../../lib/plastic/commands/graph/check"

class NodeAddFoundInTest < Plastic::TestCase
  def setup
    super
    alpha_specified
    ran("intent approve 1", "intent start 1", "node add 1 Build --criterion tests-pass")
  end

  def found = line("node add 1 Extra --criterion tests-pass --found-in n1")

  def test_a_node_added_with_found_in_prints_the_node
    assert_case found, code: 0, out: ["node: n2"]
  end

  def test_graph_show_prints_found_in_on_the_new_node_line
    ran("node add 1 Extra --criterion tests-pass --found-in n1")

    assert_case line("graph show 1"), code: 0, out: ["node: n1 open Build", "node: n2 open Extra, found in n1"]
  end

  def test_found_in_adds_no_needs_edge_and_graph_show_prints_no_edge_line
    ran("node add 1 Extra --criterion tests-pass --found-in n1")

    refute_includes line("graph show 1").out, "edge:"
  end

  def test_found_in_does_not_change_readiness
    ran("node add 1 Extra --criterion tests-pass --found-in n1")

    assert_case line("graph ready 1"), code: 0, out: ["ready: n1 Build", "ready: n2 Extra"]
  end

  def test_found_in_leaves_the_no_edge_finding_in_place
    ran("node add 1 Extra --criterion tests-pass --found-in n1")

    assert_includes line("graph check 1").out, "node n2 has no edge"
  end

  def test_a_missing_found_in_node_exits_1_names_it_and_adds_no_node
    result = line("node add 1 Extra --criterion tests-pass --found-in n9")

    assert_equal 1, result.code
    assert_includes result.err, "n9 is not a node of intent 1"
    assert_equal ["n1"], store_graphs.retrieval.structure.nodes("1").map(&:id)
  end

  def test_a_node_added_without_found_in_prints_no_found_in
    ran("node add 1 Extra --criterion tests-pass")

    refute_includes line("graph show 1").out, "found in"
  end
end
