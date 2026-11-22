# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkEdgeWriterTest < Plastic::TestCase
  def setup
    super
    @work = store_graphs.work
    @work.write_intent(title: "Alpha")
    %w[Build Test Ship].each { |title| @work.add_node(intent_id: "1", title:) }
  end

  def add(from, to) = @work.add_edge(intent_id: "1", from:, to:)

  def edges = retrieval.structure.edges("1").map { |edge| [edge.from, edge.to, edge.kind] }

  def test_an_edge_between_two_live_nodes_is_written_as_needs
    assert_equal [true, nil], add("n1", "n2")
    assert_equal [%w[n1 n2 needs]], edges
  end

  def test_an_edge_from_a_node_to_itself_is_refused_with_its_reason
    assert_equal [false, "edge n1 to n1 is refused: a node cannot need itself"], add("n1", "n1")
    assert_empty edges
  end

  def test_an_edge_to_a_missing_node_is_refused_with_its_reason
    assert_equal [false, "edge n1 to n9 is refused: n9 is not a node of intent 1"], add("n1", "n9")
  end

  def test_an_edge_from_a_missing_node_is_refused_with_its_reason
    assert_equal [false, "edge n9 to n1 is refused: n9 is not a node of intent 1"], add("n9", "n1")
  end

  def test_an_edge_to_a_removed_node_is_refused_with_its_reason
    @work.remove_node(intent_id: "1", id: "n2")

    assert_equal [false, "edge n1 to n2 is refused: n2 is removed"], add("n1", "n2")
  end

  def test_a_duplicate_edge_is_refused_with_its_reason_and_no_second_row
    add("n1", "n2")

    assert_equal [false, "edge n1 to n2 is refused: it is already there"], add("n1", "n2")
    assert_equal [%w[n1 n2 needs]], edges
  end

  def test_an_edge_that_closes_a_loop_is_refused_and_names_its_path
    add("n1", "n2")
    add("n2", "n3")

    assert_equal [false, "edge n3 to n1 is refused: it would loop, n3 -> n1 -> n2 -> n3"], add("n3", "n1")
    assert_equal [%w[n1 n2 needs], %w[n2 n3 needs]], edges
  end

  def test_a_second_path_to_a_node_is_no_loop
    add("n1", "n2")
    add("n2", "n3")

    assert_equal [true, nil], add("n1", "n3")
  end

  def test_the_edge_writer_holds_no_recursive_query
    source = File.read(File.expand_path("../../../../../lib/plastic/graph/work/edge/writer.rb", __dir__))

    refute_match(/RECURSIVE/i, source)
  end

  def test_removing_an_edge_reports_whether_one_was_there
    add("n1", "n2")

    assert_equal [true, false], [@work.remove_edge(intent_id: "1", from: "n1", to: "n2"), @work.remove_edge(intent_id: "1", from: "n1", to: "n2")]
  end
end

class WorkEdgeWriterLongChainTest < Plastic::TestCase
  LENGTH = 5000

  def setup
    super
    @work = store_graphs.work
    @work.write_intent(title: "Alpha")
    store_graphs.databases.fetch(:store).transaction do |batch|
      (1..LENGTH + 1).each { |number| batch.put(:nodes, { intent_id: "1", id: "n#{number}", kind: "work", title: "t", state: "open", updated_at: "2026-11-22T00:00:00Z" }, statement: :insert) }
      (1..LENGTH).each { |number| batch.put(:edges, { intent_id: "1", from: "n#{number}", to: "n#{number + 1}", kind: "needs" }, statement: :insert) }
    end
  end

  def test_an_edge_that_closes_a_loop_over_a_chain_of_5000_edges_is_refused_with_its_whole_path
    added, problem = @work.add_edge(intent_id: "1", from: "n#{LENGTH + 1}", to: "n1")

    refute added
    assert_includes problem, "it would loop, n5001 -> n1 -> n2 -> "
    assert_equal LENGTH + 2, problem.split(": it would loop, ").last.split(" -> ").size
  end

  def test_a_shortcut_over_a_chain_of_5000_edges_is_written
    assert_equal [true, nil], @work.add_edge(intent_id: "1", from: "n1", to: "n#{LENGTH + 1}")
  end
end
