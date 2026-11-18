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
end
