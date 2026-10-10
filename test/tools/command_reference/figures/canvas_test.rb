# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceCanvasTest < Minitest::Test
  include CommandReferenceHelper

  def canvas
    drawing = CommandReference::Figures::Canvas.new(300, "a <title> & more")
    drawing.rect(10, 10, 100, 40, "card")
    drawing.text(20, 30, "Foo<Bar> & \"baz\"", "t")
    drawing.wire([[10, 60], [10, 90]])
    drawing
  end

  def test_a_standalone_svg_spells_its_colors_out
    refute_includes canvas.to_s(true), "var("
    assert_includes canvas.to_s(true), "<style>"
  end

  def test_an_inline_svg_leaves_the_classes_to_the_page
    refute_includes canvas.to_s(false), "<style>"
  end

  def test_the_markup_is_well_formed_with_escaped_text
    document = REXML::Document.new(canvas.to_s(true))

    assert_equal "svg", document.root.name
  end

  def test_two_drawings_of_the_same_shapes_are_equal
    assert_equal canvas.to_s(true), canvas.to_s(true)
  end

  def test_the_canvas_grows_to_its_lowest_shape
    assert_operator canvas.height, :>=, 90
  end
end
