# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/graph_edges"

# GraphEdges (intent 334, n1): the shared `needs` syntax and cycle-path check
# (327 D2r-D4r, D12r). One parser for both an intent's graph.md and a
# roadmap's ## Graph section (C1) - loose about id grammar so a roadmap's
# numeric ids parse exactly like a node's kind-prefixed ids.
class GraphEdgesTest < Minitest::Test
  # --- parse: targets and the root keyword -----------------------------------

  def test_multiple_targets_parse
    result = GraphEdges.parse("- n4 needs n1 n2 n3\n")
    assert_empty result[:errors]
    assert_equal %w[n1 n2 n3], result[:edges]["n4"]
  end

  def test_needs_nothing_declares_a_root
    result = GraphEdges.parse("- v1 needs nothing\n")
    assert_empty result[:errors]
    assert_equal [], result[:edges]["v1"]
    refute_includes result[:nodes], "nothing"
  end

  def test_targeted_ids_join_the_node_set
    result = GraphEdges.parse("- n2 needs n1\n")
    assert_empty result[:errors]
    assert_includes result[:nodes], "n1"
    assert_includes result[:nodes], "n2"
  end

  # --- the live roadmap fixture (C1) ------------------------------------------

  LIVE_ROADMAP_GRAPH_SECTION = <<~SECTION.freeze
    Edges, `needs` only; the head needs the tail done. Batches are the topological layers of this list. Source: store/327--graph-of-work-under-the-roadmap/plan.md.
    - 336 needs 334 335
    - 337 needs 336
    - 338 needs 334 335
    - 339 needs 334 335
    - 340 needs 336 338 339
    - 340a needs 340
    - 340b needs 340
    - 341 needs 340b 337 342
    - 342 needs 334
    - 343 needs 340
    - 344 needs 343

    Critical paths, five hops each: 334 > 336 > 340 > 340b > 341 and 334 > 336 > 340 > 343 > 344. Ready now: 334, 335.
  SECTION

  def test_parses_the_live_roadmap_graph_section
    result = GraphEdges.parse(LIVE_ROADMAP_GRAPH_SECTION)
    assert_empty result[:errors]
    assert_equal %w[334 335], result[:edges]["336"]
    assert_equal %w[340b 337 342], result[:edges]["341"]
    # 334 and 335 are undeclared roots: they never appear on the left of a
    # "needs", only as targets, and must still join the node set (fold A5).
    assert_includes result[:nodes], "334"
    assert_includes result[:nodes], "335"
    refute result[:edges].key?("334")
    refute result[:edges].key?("335")
  end

  def test_prose_lines_are_skipped
    result = GraphEdges.parse(LIVE_ROADMAP_GRAPH_SECTION)
    assert_empty result[:errors]
    # The preamble sentence and the critical-path paragraph never look like an
    # edge line (no leading "- <id> needs"), so they contribute no node and no
    # error. Only the eleven real edge lines are counted.
    assert_equal 11, result[:edges].size
  end

  # --- parse: strict rejection of a line that looks like an edge -------------

  def test_malformed_edge_line_is_an_error
    result = GraphEdges.parse("- n2 needs\n")
    refute_empty result[:errors]
    refute result[:edges].key?("n2")
  end

  def test_prose_tail_after_targets_is_an_error
    line = "- G1 needs nothing. Node file and graph.md: ships the shared parser.\n"
    result = GraphEdges.parse(line)
    refute_empty result[:errors]
    refute result[:edges].key?("G1")
    refute_includes result[:nodes], "Node"
    refute_includes result[:nodes], "and"
  end

  # Post-execution review, non-blocking 7: `nothing` mixed with a real target
  # is not a prose tail (every token is a valid target token) - it names its
  # own defect, the root keyword used alongside a real target.
  def test_root_target_mixed_with_a_real_target_is_an_error
    result = GraphEdges.parse("- n1 needs nothing n2\n")
    refute_empty result[:errors]
    refute result[:edges].key?("n1")
    refute_includes result[:errors].join, "prose tail after targets"
    assert_includes result[:errors].join, "nothing"
  end

  def test_duplicate_node_line_is_an_error
    result = GraphEdges.parse("- n1 needs v1\n- n1 needs v2\n")
    refute_empty result[:errors]
    assert_equal %w[v1], result[:edges]["n1"]
  end

  def test_crlf_line_endings_parse
    result = GraphEdges.parse("- n1 needs v1\r\n- n2 needs n1\r\n")
    assert_empty result[:errors]
    assert_equal %w[v1], result[:edges]["n1"]
    refute_includes result[:nodes], "v1\r"
  end

  # --- cycle -------------------------------------------------------------------

  def test_cycle_is_detected
    edges = { "n1" => ["n2"], "n2" => ["n3"], "n3" => ["n1"] }
    assert_equal %w[n1 n2 n3 n1], GraphEdges.cycle(edges)
  end

  def test_self_edge_is_a_cycle
    edges = { "n1" => ["n1"] }
    assert_equal %w[n1 n1], GraphEdges.cycle(edges)
  end

  def test_cycle_returns_whole_path
    edges = { "n1" => ["n2"], "n2" => ["n3"], "n3" => ["n1"] }
    cycle = GraphEdges.cycle(edges)
    assert_kind_of Array, cycle
    assert_operator cycle.length, :>, 2
    assert_equal cycle.first, cycle.last
  end

  def test_diamond_is_not_a_cycle
    edges = { "n1" => %w[n2 n3], "n2" => ["n4"], "n3" => ["n4"], "n4" => [] }
    assert_nil GraphEdges.cycle(edges)
  end
end
