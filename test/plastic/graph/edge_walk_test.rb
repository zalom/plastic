# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/graph/edge_walk"

class EdgeWalkTest < Minitest::Test
  def walk(*pairs) = Plastic::Graph::EdgeWalk.new(pairs)

  def chain(length) = (1..length).map { |number| ["n#{number}", "n#{number + 1}"] }

  def test_a_path_along_the_edges_is_named_from_its_start_to_its_end
    assert_equal %w[n1 n2 n3], walk(%w[n1 n2], %w[n2 n3]).path("n1", "n3")
  end

  def test_no_path_against_the_direction_of_the_edges
    assert_nil walk(%w[n1 n2], %w[n2 n3]).path("n3", "n1")
  end

  def test_a_node_reaches_itself_by_a_path_of_one
    assert_equal ["n1"], walk.path("n1", "n1")
  end

  def test_a_diamond_ends_and_names_one_path
    diamond = walk(%w[a b], %w[a c], %w[b d], %w[c d])
    path = diamond.path("a", "d")

    assert_equal ["a", "d"], [path.first, path.last]
    assert_equal 3, path.size
    assert_nil diamond.path("b", "c")
  end

  def test_a_chain_of_5000_edges_ends_without_an_exception
    path = Plastic::Graph::EdgeWalk.new(chain(5000)).path("n1", "n5001")

    assert_equal 5001, path.size
    assert_equal %w[n1 n2], path.first(2)
  end

  def test_a_chain_of_diamonds_visits_each_node_once_and_ends
    pairs = (1..30).flat_map { |step| [["m#{step}", "l#{step}"], ["m#{step}", "r#{step}"], ["l#{step}", "m#{step + 1}"], ["r#{step}", "m#{step + 1}"]] }

    assert_equal 61, Plastic::Graph::EdgeWalk.new(pairs).path("m1", "m31").size
  end

  def test_a_cycle_is_named_by_the_nodes_it_runs_through
    assert_equal %w[n1 n2 n3 n1], walk(%w[n1 n2], %w[n2 n3], %w[n3 n1]).cycle("n1")
  end

  def test_a_node_off_every_cycle_has_none
    assert_nil walk(%w[n1 n2], %w[n2 n3], %w[n3 n2]).cycle("n1")
  end

  def test_a_self_edge_is_a_cycle_of_one_step
    assert_equal %w[n1 n1], walk(%w[n1 n1]).cycle("n1")
  end

  def test_a_cycle_in_a_chain_of_5000_edges_ends_without_an_exception
    cycle = Plastic::Graph::EdgeWalk.new(chain(5000) << %w[n5001 n1]).cycle("n1")

    assert_equal 5002, cycle.size
  end
end
