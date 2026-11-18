# frozen_string_literal: true

require_relative "../../../test_helper"
require "architecture_figures"

class ArchitectureFiguresShapesTextTest < Minitest::Test
  def test_text_names_its_style_and_place_and_escapes_the_content
    assert_equal %(<text class="s" x="1" y="2">a &lt; b</text>), ArchitectureFigures::Shapes.text([1, 2], "s", "a < b")
  end

  def test_text_carries_an_anchor_when_the_place_names_one
    assert_equal %(<text class="m" x="1" y="2" text-anchor="middle">x</text>), ArchitectureFigures::Shapes.text([1, 2, "middle"], "m", "x")
  end
end
