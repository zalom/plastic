# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapWriterTest < Plastic::TestCase
  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    @work = @graphs.work
  end

  def fields(title: nil, goal: nil, done: nil) = Plastic::Graph::Knowledge::Roadmap::Fields.new(title:, goal:, done:)

  def item(name, after: nil) = @work.add_item("plan", name, 1, fields: fields(title: name.upcase), after:)

  def edges = @graphs.retrieval.roadmap_edges("plan").map { |edge| [edge.from, edge.to] }

  def test_the_first_batch_writes_the_roadmap_row_and_names_an_untitled_batch
    batch = @work.write_batch("plan", 1, fields: fields(done: %w[One Two]))

    assert_equal ["Batch 1", %w[One Two]], [batch.title, batch.done_lines]
    assert_equal "plan", @graphs.retrieval.roadmap("plan").title
  end

  def test_rewriting_a_batch_keeps_the_words_left_out
    @work.write_batch("plan", 1, fields: fields(title: "First", goal: "Goal"))
    batch = @work.write_batch("plan", 1, fields: fields(goal: "New goal"))

    assert_equal ["First", "New goal"], [batch.title, batch.goal]
  end

  def test_items_take_the_next_position_in_their_batch_and_write_their_edges
    @work.write_batch("plan", 1, fields: fields)
    item("a")
    added, problem, kind = item("b", after: "a")

    assert_equal [2, nil, nil], [added.position, problem, kind]
    assert_equal [%w[a b]], edges
  end

  def test_an_item_in_a_missing_batch_fails
    assert_equal [nil, "no batch 1 on roadmap plan", :failure], item("a")
  end

  def test_an_item_after_a_missing_item_fails
    @work.write_batch("plan", 1, fields: fields)

    assert_equal [nil, "no item z on roadmap plan", :failure], item("a", after: "z")
  end

  def test_an_edge_that_would_loop_is_refused
    @work.write_batch("plan", 1, fields: fields)
    item("a")
    item("b", after: "a")

    assert_equal [nil, "an edge from b to a would loop", :refusal], item("a", after: "b")
    assert_equal [%w[a b]], edges
  end

  def test_an_item_after_itself_is_refused
    @work.write_batch("plan", 1, fields: fields)
    item("a")

    assert_equal :refusal, item("a", after: "a").last
  end

  def test_dropping_an_item_marks_it_and_reports_whether_a_row_changed
    @work.write_batch("plan", 1, fields: fields)
    item("a")

    assert_equal [true, false], [@work.drop_item("plan", "a"), @work.drop_item("plan", "z")]
    assert_predicate @graphs.retrieval.roadmap_items("plan").first, :dropped?
  end

  def test_removing_an_edge_reports_true_then_false
    @work.write_batch("plan", 1, fields: fields)
    item("a")
    item("b", after: "a")

    assert_equal [true, false], Array.new(2) { @work.remove_roadmap_edge("plan", "a", "b") }
  end

  def test_log_lines_take_the_next_position_and_the_session
    lines = %w[first second].map { |text| @work.add_log("plan", text) }

    assert_equal [[1, "first", "s-1"], [2, "second", "s-1"]], lines.map { |line| [line.position, line.text, line.session_id] }
  end
end
