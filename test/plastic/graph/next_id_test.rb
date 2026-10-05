# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/next_id"

class NextIdTest < Minitest::Test
  Row = Struct.new(:id)

  def test_counts_on_from_the_highest_id_under_the_prefix
    rows = [Row.new("D1"), Row.new("D3"), Row.new("D38f")]

    assert_equal "D4", Plastic::Graph::NextId.after(rows, prefix: "D")
  end

  def test_the_first_id_after_no_ids_is_one
    assert_equal "n1", Plastic::Graph::NextId.after([], prefix: "n")
  end
end
