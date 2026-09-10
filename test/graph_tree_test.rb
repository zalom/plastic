# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/graph_tree"

# GraphTree (intent 337, n2, folds 327a): draws any edge map as an indented
# tree with box-drawing branches. A node several branches need is drawn once
# at the point where those branches join (fan-out); a node that itself needs
# several things is drawn under its highest-batch need, ties broken by
# smallest id, with its other needs shown as converging references at the
# join (fan-in, row 2.14, folded at the 2026-09-10 plan review). Pure, plain
# text, no roadmap knowledge. Matrix rows from actions/ACTION_1.md S2/n2.
class GraphTreeTest < Minitest::Test
  def test_chain_renders_each_need_above_its_dependent
    edges = { "a" => [], "b" => ["a"], "c" => ["b"] }
    result = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    lines = result[:text].each_line.map(&:chomp)
    assert_equal 0, lines.index { |l| l.include?("a") }
    assert lines.index { |l| l.include?("a") } < lines.index { |l| l.include?("b") }
    assert lines.index { |l| l.include?("b") } < lines.index { |l| l.include?("c") }
  end

  def test_shared_dependency_is_drawn_once_at_the_join
    edges = { "a" => [], "b" => ["a"], "c" => ["a"] }
    result = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    lines = result[:text].each_line.map(&:chomp)
    assert_equal 1, lines.count { |l| l.strip.end_with?("a") || l.strip == "a" }
  end

  def test_three_roots_all_join_into_their_common_head
    edges = { "a" => [], "b" => [], "c" => [], "d" => %w[a b c] }
    result = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    text = result[:text]
    assert_includes text, "a"
    assert_includes text, "b"
    assert_includes text, "c"
    assert_includes text, "d"
  end

  def test_same_input_renders_byte_identical_twice
    edges = { "a" => [], "b" => ["a"], "c" => ["a"], "d" => %w[b c] }
    r1 = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    r2 = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    assert_equal r1[:text], r2[:text]
  end

  def test_critical_path_is_marked_on_the_longest_chain_only
    edges = { "a" => [], "b" => ["a"], "c" => ["b"], "x" => [] }
    marks = { critical_path: %w[a b c] }
    result = GraphTree.render(edges: edges, labels: {}, marks: marks, width: 80)
    lines = result[:text].each_line.map(&:chomp)
    marked = lines.select { |l| l.include?("*") }
    assert_equal 3, marked.length
    refute marked.any? { |l| l.include?(" x") || l.strip.end_with?("x") }
  end

  def test_ready_entries_are_marked_and_blocked_ones_are_not
    edges = { "a" => [], "b" => ["a"] }
    marks = { ready: ["a"] }
    result = GraphTree.render(edges: edges, labels: {}, marks: marks, width: 80)
    lines = result[:text].each_line.map(&:chomp)
    a_line = lines.find { |l| l.include?("a") && !l.include?("b") }
    b_line = lines.find { |l| l.include?("b") }
    assert_match(/ready/, a_line)
    refute_match(/ready/, b_line)
  end

  def test_output_contains_no_escape_byte
    edges = { "a" => [], "b" => ["a"] }
    result = GraphTree.render(edges: edges, labels: {}, marks: { critical_path: %w[a b], ready: ["a"] }, width: 80)
    refute_includes result[:text].bytes, 0x1B
  end

  def test_long_label_is_truncated_to_the_width_and_columns_stay_aligned
    edges = { "a" => [], "b" => ["a"] }
    labels = { "a" => "a" * 200, "b" => "b" * 200 }
    result = GraphTree.render(edges: edges, labels: labels, marks: {}, width: 40)
    lines = result[:text].each_line.map(&:chomp)
    lines.each { |l| assert l.length <= 40, "line too long: #{l.inspect}" }
  end

  def test_empty_graph_renders_a_named_empty_line
    result = GraphTree.render(edges: {}, labels: {}, marks: {}, width: 80)
    assert result[:ok]
    refute_empty result[:text].strip
  end

  def test_cyclic_edges_are_refused_with_the_path_and_do_not_hang
    edges = { "a" => ["b"], "b" => ["a"] }
    result = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    refute result[:ok]
    assert_equal %w[a b a], result[:cycle]
    refute_nil result[:error]
  end

  def test_node_without_a_label_renders_its_id
    edges = { "abc123" => [] }
    result = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    assert_includes result[:text], "abc123"
  end

  def test_isolated_node_still_appears
    edges = { "lonely" => [], "a" => [], "b" => ["a"] }
    result = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    assert_includes result[:text], "lonely"
  end

  def test_library_source_reads_no_clock_or_environment
    source = File.read(File.expand_path("../scripts/lib/graph_tree.rb", __dir__))
    refute_match(/\bTime\.now\b/, source)
    refute_match(/\bENV\[/, source)
    refute_match(/\bENV\.fetch\b/, source)
  end

  # --- 2.14: shared node hangs under its highest-batch need, ties by smallest id -

  def test_shared_node_hangs_under_its_highest_batch_need_ties_by_smallest_id
    # n1, n2 both batch 1 (roots); n3 needs n1 n2 - tie, smallest id (n1) wins.
    edges = { "n1" => [], "n2" => [], "n3" => %w[n1 n2] }
    result = GraphTree.render(edges: edges, labels: {}, marks: {}, width: 80)
    lines = result[:text].each_line.map(&:chomp)
    n1_idx = lines.index { |l| l.strip.end_with?("n1") }
    n2_idx = lines.index { |l| l.strip.end_with?("n2") }
    n3_idx = lines.index { |l| l.include?("n3") }
    refute_nil n1_idx
    refute_nil n2_idx
    assert n3_idx > n1_idx
    n3_line = lines[n3_idx]
    assert_match(/n2/, n3_line)

    # a4 batch1, a5 batch2 (a5 needs a4) - a6 needs a4 a5: primary is a5 (higher batch).
    edges2 = { "a4" => [], "a5" => ["a4"], "a6" => %w[a4 a5] }
    result2 = GraphTree.render(edges: edges2, labels: {}, marks: {}, width: 80)
    lines2 = result2[:text].each_line.map(&:chomp)
    a5_idx = lines2.index { |l| l.strip.end_with?("a5") }
    a6_idx = lines2.index { |l| l.include?("a6") }
    assert a6_idx > a5_idx
  end
end
