# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/routine"

class EdgeTest < Minitest::Test
  KEYS = %i[code_a code_b code_c].freeze

  def edge(from, to, on: nil) = Plastic::Routine::Edge.new(from:, on:, to:)

  def test_a_plain_edge_carries_every_outcome
    assert edge(:code_a, :code_b).carries?(:refused)
  end

  def test_an_on_edge_carries_only_its_outcome
    on_edge = edge(:code_a, :code_b, on: :done)

    assert_predicate [on_edge.carries?(:done), !on_edge.carries?(:refused)], :all?
  end

  def test_an_on_line_for_an_outcome_the_workflow_never_returns_is_stray
    assert edge(:code_a, :code_b, on: :lost).stray?(%i[done refused])
  end

  def test_a_plain_edge_is_never_stray
    refute edge(:code_a, :code_b).stray?([])
  end

  def test_a_forward_edge_has_no_problem
    assert_nil edge(:code_a, :code_c).problem(KEYS)
  end

  def test_an_edge_to_noop_has_no_problem
    assert_nil edge(:code_c, :noop).problem(KEYS)
  end

  def test_an_edge_to_a_key_outside_the_chain_names_the_target
    assert_equal "code_z is a target but not in the chain", edge(:code_a, :code_z).problem(KEYS)
  end

  def test_an_edge_that_points_backward_names_both_keys
    assert_equal "code_c -> code_a points backward; a chain only moves forward", edge(:code_c, :code_a).problem(KEYS)
  end
end
