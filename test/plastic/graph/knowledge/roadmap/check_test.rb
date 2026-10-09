# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/roadmap/check"

class KnowledgeRoadmapCheckTest < Plastic::TestCase
  def setup
    super
    @work = store_graphs.work
    @work.write_batch("plan", 1, fields: fields)
    @work.add_item("plan", "a", 1, fields:, after: nil)
    @work.add_item("plan", "b", 1, fields:, after: "a")
  end

  def fields = Plastic::Graph::Knowledge::Roadmap::Fields.new(title: "T", goal: nil, done: nil)

  def findings = Plastic::Graph::Knowledge::Roadmap::Check.new(retrieval, "plan").all

  def put(table, row) = store_graphs.databases[:work].transaction { |batch| batch.put(table, row) }

  def test_a_roadmap_with_only_forward_edges_has_no_finding
    assert_empty findings
  end

  def test_an_edge_to_an_item_not_on_the_roadmap_is_named
    put(:roadmap_edges, { roadmap: "plan", from: "b", to: "z", kind: "after" })

    assert_equal ["edge b to z names an item not on roadmap plan"], findings
  end

  def test_a_loop_names_every_item_on_it
    put(:roadmap_edges, { roadmap: "plan", from: "b", to: "a", kind: "after" })

    assert_equal ["item a loops back to itself", "item b loops back to itself"], findings
  end

  def test_an_item_naming_a_missing_intent_is_named
    @work.open_item("plan", "a", "9")

    assert_equal ["item a names no intent 9"], findings
  end

  def test_an_item_naming_a_present_intent_is_not
    @work.open_item("plan", "a", @work.write_intent(title: "Alpha").intent_id)

    assert_empty findings
  end
end
