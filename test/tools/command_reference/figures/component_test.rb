# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceComponentFigureTest < Minitest::Test
  include CommandReferenceHelper

  def svg(words) = CommandReference::Figures::Component.new(page(words)).canvas.standalone

  def test_the_component_svg_is_well_formed_for_a_chain_a_command_and_a_hook
    ["intent end", "project list", "hook end"].each { |words| assert_equal "svg", REXML::Document.new(svg(words)).root.name, words }
  end

  def test_a_command_with_nothing_found_says_no_database_was_found_in_the_code
    assert_includes svg("version"), "no database found in the code"
  end

  def test_the_component_and_call_drawings_of_a_hook_and_a_no_chain_command_parse
    %w[hook\ end project\ list].each do |words|
      [svg(words), CommandReference::Figures::Call.new(page(words)).canvas.standalone].each do |drawing|
        assert_equal "svg", REXML::Document.new(drawing).root.name, words
      end
    end
  end

  def test_no_built_drawing_of_a_command_uses_a_bare_css_variable
    drawings = CommandReferenceHelper.files.select { |path, _| path.end_with?(".svg") }

    refute_empty drawings
    drawings.each { |path, body| refute_includes body, "var(", path }
  end

  def test_a_database_lists_its_tables
    assert_includes svg("node add"), "work_graph.db"
    assert_includes svg("node add"), "nodes"
  end
end
