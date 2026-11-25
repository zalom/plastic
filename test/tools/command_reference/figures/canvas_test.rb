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

  def test_no_built_drawing_of_a_command_uses_a_bare_css_variable
    drawings = CommandReferenceHelper.files.select { |path, _| path.end_with?(".svg") }

    refute_empty drawings
    drawings.each { |path, body| refute_includes body, "var(", path }
  end

  def test_two_drawings_of_the_same_shapes_are_equal
    assert_equal canvas.standalone, canvas.standalone
  end

  def test_the_canvas_grows_to_its_lowest_shape
    assert_operator canvas.height, :>=, 90
  end

  def test_a_line_through_points_has_no_arrow_and_reaches_down_to_its_lowest_point
    figures = CommandReference::Figures
    points = [figures::Point.new(10, 20), figures::Point.new(10, 50), figures::Point.new(40, 50)]
    drawing = figures::Canvas.new(300, "title")
    drawing.line(points, "wire-end")

    assert_includes drawing.to_s, %(<path d="M 10 20 L 10 50 L 40 50" class="wire-end"/>)
    refute_includes drawing.to_s, "head"
    assert_equal 50, drawing.height
  end

  def test_lines_of_words_stack_at_a_step_below_their_origin
    figures = CommandReference::Figures
    drawing = figures::Canvas.new(300, "title")
    drawing.stack(figures::Point.new(5, 10), %w[one two], "t", 17)

    assert_includes drawing.to_s, %(x="5" y="10" class="t" text-anchor="start">one<)
    assert_includes drawing.to_s, %(x="5" y="27" class="t" text-anchor="start">two<)
  end

  def test_a_box_gives_the_points_of_a_branch_to_a_bus_and_of_a_drop_below_it
    box = CommandReference::Figures::Box.new(10, 20, 100, 40)

    assert_equal ["60 60", "60 90", "30 90", "30 98"], box.branch_to(30, 90).map(&:to_s)
    assert_equal ["60 60", "60 86"], box.drop(26).map(&:to_s)
  end

  def test_a_point_goes_down_to_a_level_and_bends_around_an_elbow_only_when_the_levels_differ
    point = CommandReference::Figures::Point.new(10, 20)
    level = CommandReference::Figures::Point.new(90, 20)
    lower = CommandReference::Figures::Point.new(90, 60)

    assert_equal ["10 20", "10 70"], point.down_to(70).map(&:to_s)
    assert_equal ["10 20", "90 20"], point.elbow_to(level, 50).map(&:to_s)
    assert_equal ["10 20", "50 20", "50 60", "90 60"], point.elbow_to(lower, 50).map(&:to_s)
  end
end
