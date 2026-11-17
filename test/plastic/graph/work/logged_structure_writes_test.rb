# frozen_string_literal: true

require_relative "../../../test_helper"

# Node, edge and archive writes leave one work_log line each; a write that changed nothing leaves none.
class WorkLoggedStructureWritesTest < Plastic::TestCase
  fixtures :empty

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def work = graphs.work

  def lines(id = "1") = graphs.retrieval.structure.work_log(id)

  def kinds(id = "1") = lines(id).map(&:kind)

  def intent(title = "Alpha") = work.write_intent(title:)

  def work_intent = graphs.retrieval.intent("1")

  def test_adding_and_removing_a_node_append_a_line_each
    intent
    work.add_node(intent_id: "1", title: "Build")
    work.remove_node(intent_id: "1", id: "n1")

    assert_equal [%w[added n1 Build], %w[removed n1 Build]], lines.drop(1).map { |line| line.values_at(:kind, :node, :text) }
  end

  def edge_lines = lines.select { |line| line.kind.start_with?("edge") }

  def add_then_remove_edge
    intent
    2.times { work.add_node(intent_id: "1", title: "Step") }
    work.add_edge(intent_id: "1", from: "n2", to: "n1")
    work.remove_edge(intent_id: "1", from: "n2", to: "n1")
  end

  def test_adding_and_removing_an_edge_append_a_line_naming_both_nodes
    add_then_remove_edge

    assert_equal [%w[edge_added edge_removed], [true, true]],
      [edge_lines.map(&:kind), edge_lines.map { |line| line.text.include?("n2") && line.text.include?("n1") }]
  end

  def test_an_edge_move_that_changed_nothing_appends_no_line
    intent
    work.remove_edge(intent_id: "1", from: "n2", to: "n1")

    assert_equal %w[opened], kinds
  end

  def test_archiving_and_unarchiving_append_a_line_each
    intent
    work.print_intent("1")
    work.note_intent(work_intent, "note", "why it ends")
    work.abandon_intent("1")
    work.archive_intent("1")
    work.unarchive_intent("1")

    assert_equal %w[archived unarchived], kinds.last(2)
  end

  class CappedNowhere
    def claim_node(**) = [:capped, nil]
  end

  class NodesThatCapNowhere < Plastic::Graph::Work::Writers
    def nodes = (@nodes ||= CappedNowhere.new)
  end

  def test_a_claim_that_is_capped_with_no_node_appends_no_line_and_raises_nothing
    intent
    open = graphs
    writers = NodesThatCapNowhere.new(open.databases, open.retrieval, folder, "s-1")
    status, node = Plastic::Graph::Work::LoggedWrites.new(writers).claim_node(intent_id: "1", id: "n1", by: "s-1")

    assert_equal [:capped, nil, %w[opened]], [status, node, kinds]
  end
end
