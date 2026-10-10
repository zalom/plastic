# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceCanvasTest < Minitest::Test
  include CommandReferenceHelper

  def canvas
    drawing = CommandReference::Figures::Canvas.new(300, "a <title> & more")
    drawing.rect(CommandReference::Figures::Box.new(10, 10, 100, 40), "card")
    drawing.text(CommandReference::Figures::Point.new(20, 30), "Foo<Bar> & \"baz\"", "t")
    drawing.wire([CommandReference::Figures::Point.new(10, 60), CommandReference::Figures::Point.new(10, 90)])
    drawing
  end

  def test_a_standalone_svg_spells_its_colors_out
    refute_includes canvas.standalone, "var("
    assert_includes canvas.standalone, "<style>"
  end

  def test_an_inline_svg_leaves_the_classes_to_the_page
    refute_includes canvas.to_s, "<style>"
  end

  def test_the_markup_is_well_formed_with_escaped_text
    document = REXML::Document.new(canvas.standalone)

    assert_equal "svg", document.root.name
  end

  def test_two_drawings_of_the_same_shapes_are_equal
    assert_equal canvas.standalone, canvas.standalone
  end

  def test_the_canvas_grows_to_its_lowest_shape
    assert_operator canvas.height, :>=, 90
  end
end
