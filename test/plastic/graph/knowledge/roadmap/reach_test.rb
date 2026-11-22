# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapReachTest < Plastic::TestCase
  Roadmap = Plastic::Graph::Knowledge::Roadmap

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    fields = Roadmap::Fields.new(title: nil, goal: nil, done: nil)
    @graphs.work.write_batch("plan", 1, fields:)
    @graphs.work.add_item("plan", "a", 1, fields:, needs: [])
    @graphs.work.add_item("plan", "b", 1, fields:, needs: ["a"])
  end

  def reach = Roadmap::Reach.new(@graphs.databases, @graphs.retrieval, "plan")

  def test_an_edge_back_along_an_edge_closes_a_loop
    assert reach.loop?("b", "a")
  end

  def test_an_edge_along_an_edge_closes_no_loop
    refute reach.loop?("a", "b")
  end

  def test_an_edge_from_an_item_to_itself_is_a_loop
    assert reach.loop?("a", "a")
  end

  def test_a_loop_names_its_path
    assert_equal %w[b a b], reach.loop_path("b", "a")
    assert_nil reach.loop_path("a", "b")
  end

  def test_the_reach_uses_the_edge_walk_and_holds_no_recursive_query
    source = File.read(File.expand_path("../../../../../lib/plastic/graph/knowledge/roadmap/reach.rb", __dir__))

    assert_includes source, "EdgeWalk"
    refute_match(/RECURSIVE/i, source)
  end
end

class KnowledgeRoadmapReachLongChainTest < Plastic::TestCase
  Roadmap = Plastic::Graph::Knowledge::Roadmap
  LENGTH = 5000

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    @graphs.work.write_batch("plan", 1, fields: Roadmap::Fields.new(title: nil, goal: nil, done: nil))
    @graphs.databases.fetch(:store).transaction do |batch|
      (1..LENGTH).each { |number| batch.put(:roadmap_edges, { roadmap: "plan", from: "i#{number}", to: "i#{number + 1}", kind: "after" }) }
    end
  end

  def reach = Roadmap::Reach.new(@graphs.databases, @graphs.retrieval, "plan")

  def test_an_edge_closing_a_chain_of_5000_edges_is_a_loop_and_ends_without_an_exception
    assert reach.loop?("i5001", "i1")
    refute reach.loop?("i1", "i5001")
  end
end
