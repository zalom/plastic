# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceTouchesFigureTest < Minitest::Test
  include CommandReferenceHelper

  def svg(words) = CommandReference::Figures::Touches.new(page(words)).canvas.standalone

  def test_the_touches_svg_is_well_formed_for_a_routine_a_command_and_a_hook
    ["intent new", "project list", "hook stop", "version"].each do |words|
      assert_equal "svg", REXML::Document.new(svg(words)).root.name, words
    end
  end

  def test_the_touches_svg_names_every_database_and_printed_file
    drawing = svg("intent new")
    touches = page("intent new").touches

    refute_empty touches.database_files
    (touches.database_files + touches.files).each { |name| assert_includes drawing, name }
  end

  def test_the_touches_svg_puts_the_reads_left_and_the_writes_right_of_the_command
    drawing = svg("intent end")

    assert_includes drawing, "READS"
    assert_includes drawing, "WRITES"
    assert_includes drawing, "PRINTED FILES"
  end

  def test_a_command_that_touches_no_store_draws_one_box_saying_so
    assert_includes svg("version"), "no database found in the code"
  end

  def test_the_touches_svg_is_titled_with_the_command
    assert_includes svg("intent new"), "<title>What one call of plastic intent new reads, writes and prints</title>"
  end

  def test_the_touches_svg_holds_no_timestamp_or_absolute_path
    refute_match(%r{20\d\d-\d\d-\d\d|/Users/}, svg("intent new"))
  end
end
