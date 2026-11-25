# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/knowledge/ruling_order"

class RulingOrderTest < Minitest::Test
  Entry = Struct.new(:id)
  ORDER = Plastic::Graph::Knowledge::RulingOrder

  def rulings = %w[D10 D2 D1.2 D1 D10.1 D1.1].map { |id| Entry.new(id) }

  def test_rulings_are_sorted_by_their_number_and_each_addition_follows_its_decision
    assert_equal %w[D1 D1.1 D1.2 D2 D10 D10.1], ORDER.sorted(rulings).map(&:id)
  end

  def test_the_additions_of_a_decision_are_the_ones_numbered_under_it
    assert_equal %w[D1.1 D1.2], ORDER.additions(rulings, "D1").map(&:id)
  end
end
