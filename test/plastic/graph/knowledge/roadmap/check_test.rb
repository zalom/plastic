# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/roadmap/check"

class KnowledgeRoadmapCheckTest < Plastic::TestCase
  def setup
    super
    @work = store_graphs.work
    @work.write_batch("plan", 1, fields: fields)
    @work.add_item("plan", "a", 1, fields:, needs: nil)
    @work.add_item("plan", "b", 1, fields:, needs: "a")
  end

  def fields = Plastic::Graph::Knowledge::Roadmap::Fields.new(title: "T", goal: nil, done: nil)

  def findings = Plastic::Graph::Knowledge::Roadmap::Check.new(retrieval, "plan").all

  def put(table, row) = store_graphs.databases.fetch(:store).transaction { |batch| batch.put(table, row) }

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

  def test_the_check_holds_no_recursive_method_and_no_recursive_query
    source = File.read(File.expand_path("../../../../../lib/plastic/graph/knowledge/roadmap/check.rb", __dir__))

    assert_includes source, "EdgeWalk"
    refute_match(/RECURSIVE/i, source)
    refute_match(/def loop\?/, source)
  end
end

class KnowledgeRoadmapCheckLongTest < Minitest::Test
  Item = Struct.new(:item, :intent_id)
  Edge = Struct.new(:from, :to)
  Roadmaps = Struct.new(:item_rows, :edge_rows) do
    def items(_slug) = item_rows

    def edges(_slug) = edge_rows
  end
  Retrieval = Struct.new(:roadmaps) do
    def intent(_id) = nil
  end

  def findings(names, pairs)
    roadmaps = Roadmaps.new(names.map { |name| Item.new(name, nil) }, pairs.map { |from, to| Edge.new(from, to) })
    Plastic::Graph::Knowledge::Roadmap::Check.new(Retrieval.new(roadmaps), "plan").all
  end

  def test_a_chain_of_5000_items_ends_with_no_finding_and_no_exception
    names = (1..5000).map { |number| "i#{number}" }

    assert_empty findings(names, names.each_cons(2).to_a)
  end

  def test_a_chain_of_30_diamonds_has_no_finding
    names = (1..30).flat_map { |step| ["m#{step}", "l#{step}", "r#{step}"] } << "m31"
    pairs = (1..30).flat_map { |step| [["m#{step}", "l#{step}"], ["m#{step}", "r#{step}"], ["l#{step}", "m#{step + 1}"], ["r#{step}", "m#{step + 1}"]] }

    assert_empty findings(names, pairs)
  end

  def test_a_loop_closing_a_chain_of_5000_items_names_each_item_on_it
    names = (1..5000).map { |number| "i#{number}" }

    assert_equal 5000, findings(names, names.each_cons(2).to_a << [names.last, names.first]).size
  end
end
