# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapItemAdderTest < Plastic::TestCase
  Roadmap = Plastic::Graph::Knowledge::Roadmap

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    @fields = Roadmap::Fields.new(title: "A", goal: nil, done: nil)
    @graphs.work.write_batch("plan", 1, fields: @fields)
    @adder = Roadmap::ItemAdder.new(@graphs.databases, @graphs.retrieval, clock: Time)
  end

  def test_an_added_item_comes_back_with_its_position
    row, problem, kind = @adder.add_item("plan", "a", 1, fields: @fields, needs: nil)

    assert_equal [1, nil, nil], [row.position, problem, kind]
  end

  def test_a_refused_item_comes_back_with_the_reason
    assert_equal [nil, "no batch 2 on roadmap plan", :failure], @adder.add_item("plan", "a", 2, fields: @fields, needs: nil)
  end
end
