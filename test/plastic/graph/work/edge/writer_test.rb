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

  def edges = retrieval.edges("1").map { |edge| [edge.from, edge.to, edge.kind] }

  def test_an_edge_between_two_live_nodes_is_written_as_needs
    assert add("n1", "n2")
    assert_equal [%w[n1 n2 needs]], edges
  end

  def test_an_edge_from_a_node_to_itself_is_refused
    refute add("n1", "n1")
    assert_empty edges
  end

  def test_an_edge_to_a_missing_node_is_refused
    refute add("n1", "n9")
  end

  def test_an_edge_to_a_removed_node_is_refused
    @work.remove_node(intent_id: "1", id: "n2")

    refute add("n1", "n2")
  end

  def test_an_edge_that_closes_a_loop_is_refused
    add("n1", "n2")
    add("n2", "n3")

    refute add("n3", "n1")
    assert_equal [%w[n1 n2 needs], %w[n2 n3 needs]], edges
  end

  def test_removing_an_edge_reports_whether_one_was_there
    add("n1", "n2")

    assert_equal [true, false], [@work.remove_edge(intent_id: "1", from: "n1", to: "n2"), @work.remove_edge(intent_id: "1", from: "n1", to: "n2")]
  end
end
