# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/work/node/counts"

class CountsTest < Minitest::Test
  Row = Data.define(:state)

  def line(*states) = Plastic::Graph::Work::Node::Counts.new(states.map { |state| Row.new(state) }).line

  def test_no_nodes_say_so
    assert_equal "no nodes", line
  end

  def test_the_line_counts_each_state_in_first_seen_order
    assert_equal "open: 2, done: 1", line("open", "done", "open")
  end
end
