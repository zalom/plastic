# frozen_string_literal: true

require_relative "../../../test_helper"
require "architecture_figures"

class ArchitectureFiguresShapesAnchoredTest < Minitest::Test
  Frame = Data.define(:left, :top, :width, :height) { include ArchitectureFigures::Shapes::Anchored }

  def frame = Frame.new(10, 20, 100, 40)

  def test_the_edges_follow_from_the_corner_and_the_size
    assert_equal [10, 20, 110, 60], frame.bounds
  end

  def test_an_anchor_sits_at_the_middle_of_a_side_unless_a_fraction_moves_it
    assert_equal [[110, 40], [60, 20], [35.0, 60]], [frame.anchor(:right), frame.anchor(:top), frame.anchor(:bottom, 0.25)]
  end
end
