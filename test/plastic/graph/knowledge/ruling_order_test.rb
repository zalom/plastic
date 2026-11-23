# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/knowledge/ruling_order"

class RulingOrderTest < Minitest::Test
  Entry = Struct.new(:id, :supersedes)
  ORDER = Plastic::Graph::Knowledge::RulingOrder

  def rulings = [Entry.new("D10", nil), Entry.new("D2", "D1"), Entry.new("D1", nil)]

  def test_rulings_are_sorted_by_their_number
    assert_equal %w[D1 D2 D10], ORDER.sorted(rulings).map(&:id)
  end

  def test_the_superseded_ids_are_those_another_ruling_names
    assert_equal ["D1"], ORDER.superseded_ids(rulings).to_a
  end

  def test_the_rulings_in_force_leave_out_the_superseded_ones
    assert_equal %w[D2 D10], ORDER.in_force(rulings).map(&:id)
  end
end
