# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapRowsTest < Plastic::TestCase
  Roadmap = Plastic::Graph::Knowledge::Roadmap

  def rows = Roadmap::Rows.new("plan", "T")

  def fields = Roadmap::Fields.new(title: "Title", goal: "Goal", done: %w[One Two])

  def test_the_roadmap_row_is_named_by_its_slug_and_opened_now
    assert_equal({ slug: "plan", title: "plan", goal: nil, opened_at: "T", updated_at: "T" }, rows.roadmap)
  end

  def test_a_batch_row_joins_the_done_lines
    assert_equal({ roadmap: "plan", position: 2, title: "Title", goal: "Goal", done: "One\nTwo", updated_at: "T" }, rows.batch(2, fields))
  end

  def test_an_item_row_starts_with_no_intent_and_no_mark
    row = rows.item("a", 1, 3, fields)

    assert_equal ["a", 1, 3, nil, nil], row.values_at(:item, :batch, :position, :intent_id, :mark)
  end

  def test_an_edge_row_is_an_after_edge
    assert_equal({ roadmap: "plan", from: "a", to: "b", kind: "after" }, rows.edge("a", "b"))
  end

  def test_a_log_row_carries_its_position_and_session
    assert_equal({ roadmap: "plan", position: 4, at: "T", text: "said", session_id: "s-1" }, rows.log(4, "said", "s-1"))
  end
end
