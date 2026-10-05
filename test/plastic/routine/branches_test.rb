# frozen_string_literal: true

require_relative "../../test_helper"

class BranchesTest < Plastic::TestCase
  def chain = Plastic::Routine::Chain.new(Fixtures::Routine)

  def test_an_on_line_adds_an_edge_for_its_outcome
    edges = chain.tap { |built| Plastic::Routine::Branches.new(built, :code_greet).on(:done, next: :noop) }.edges

    assert_equal [[:code_greet, :done, :noop]], edges.map { |edge| [edge.from, edge.on, edge.to] }
  end

  def test_an_on_line_with_no_next_raises
    assert_raises(KeyError) { Plastic::Routine::Branches.new(chain, :code_greet).on(:done) }
  end
end
