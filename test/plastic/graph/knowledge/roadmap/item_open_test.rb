# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapItemOpenTest < Plastic::TestCase
  def setup
    super
    @work = store_graphs.work
    @work.write_batch("plan", 1, fields: fields(goal: "Ship batch", done: "Batch done"))
    @work.add_item("plan", "a", 1, fields: fields(title: "Item A", goal: "Ship A", done: "A done"), after: nil)
    @work.add_item("plan", "b", 1, fields: fields(title: "Item B"), after: "a")
  end

  def fields(title: nil, goal: nil, done: nil) = Plastic::Graph::Knowledge::Roadmap::Fields.new(title:, goal:, done:)

  def start(item) = store_graphs.work.open_roadmap_item("plan", item)

  def test_a_ready_item_opens_an_intent_named_after_it
    assert_equal ["1", nil, nil], start("a")
    assert_equal "Item A", retrieval.intent("1").title
  end

  def test_the_opened_intent_carries_the_item_goal_in_its_spec
    start("a")

    assert_equal ["Ship A"], Plastic::Graph::Knowledge::Spec.new(retrieval, "1").goal_lines.last(1)
  end

  def test_the_opened_intent_links_back_to_the_roadmap
    start("a")

    assert_equal [["1", "roadmap:plan", "source"]], retrieval.links("1").map { |link| [link.from_ref, link.to_ref, link.kind] }
  end

  def test_the_started_item_records_its_intent
    start("a")

    assert_equal "1", retrieval.roadmap_items("plan").first.intent_id
  end

  def test_a_missing_item_fails
    assert_equal [nil, "no item z on roadmap plan", :failure], start("z")
  end

  def test_a_blocked_item_is_refused_and_opens_no_intent
    assert_equal [nil, "item b is blocked, not ready", :refusal], start("b")
    assert_nil retrieval.intent("1")
  end

  def test_a_started_item_cannot_start_twice
    start("a")

    assert_equal [nil, "item a already has an intent", :refusal], start("a")
  end
end
