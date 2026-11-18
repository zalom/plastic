# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapItemMarksTest < Plastic::TestCase
  Roadmap = Plastic::Graph::Knowledge::Roadmap

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    fields = Roadmap::Fields.new(title: nil, goal: nil, done: nil)
    @graphs.work.write_batch("plan", 1, fields:)
    @graphs.work.add_item("plan", "a", 1, fields:, needs: [])
    @marks = Roadmap::ItemMarks.new(@graphs.databases, @graphs.retrieval, clock: Time)
  end

  def item = @graphs.retrieval.roadmaps.items("plan").first

  def test_opening_an_item_records_its_intent
    assert_equal [true, "7"], [@marks.open_item("plan", "a", "7"), item.intent_id]
  end

  def test_dropping_an_item_marks_it_dropped
    assert_equal [true, "dropped"], [@marks.drop_item("plan", "a"), item.mark]
  end

  def test_an_item_not_on_the_roadmap_changes_nothing
    assert_equal [false, false], [@marks.open_item("plan", "z", "7"), @marks.drop_item("plan", "z")]
  end
end
