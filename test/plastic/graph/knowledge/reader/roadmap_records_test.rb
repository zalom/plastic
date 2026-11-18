# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderRoadmapRecordsTest < Plastic::TestCase
  Records = Plastic::Graph::Knowledge::Reader::RoadmapRecords

  LINES = [
    "title: Plan", "", "## Batch 1: First", "title: First", "- [ ] item", "item: a", "position: 1",
    "## Graph", "- edge", "from: a", "to: b", "kind: needs"
  ].freeze

  def test_the_head_holds_the_labels_before_the_first_section
    assert_equal "Plan", Records.new(LINES).head["title"]
  end

  def test_a_batch_heading_starts_a_batch_with_its_position
    assert_equal %w[1], Records.new(LINES).of(:batches).map { |batch| batch["position"] }
  end

  def test_an_item_under_a_batch_knows_its_batch
    assert_equal [{ "batch" => "1", "item" => "a", "position" => "1" }], Records.new(LINES).of(:items)
  end

  def test_the_graph_section_lists_edges
    assert_equal [%w[a b needs]], Records.new(LINES).of(:edges).map { |edge| edge.values_at("from", "to", "kind") }
  end

  def test_a_value_that_is_empty_is_no_value
    assert_equal [nil, nil, "x"], [Records.blank(""), Records.blank(nil), Records.blank("x")]
  end
end
