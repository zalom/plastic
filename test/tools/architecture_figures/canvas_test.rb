# frozen_string_literal: true

require_relative "../../test_helper"
require "rexml/document"
require "architecture_figures"

class ArchitectureFiguresCanvasTest < Minitest::Test
  def test_text_comes_out_escaped_and_the_markup_stays_well_formed
    canvas = ArchitectureFigures::Canvas.new("sample.svg", 200, 80, "a < b & c", "a < b & c")
    canvas.add(ArchitectureFigures::Shapes::Label.new(left: 10, top: 20, text: "a < b & c", style: "s"))
    svg = canvas.to_svg

    assert_includes svg, "a &lt; b &amp; c"
    assert_equal "a < b & c", REXML::Document.new(svg).get_elements("//text").first.text
  end
end
