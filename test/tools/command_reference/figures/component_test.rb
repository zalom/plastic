# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceComponentFigureTest < Minitest::Test
  include CommandReferenceHelper

  def svg(words) = CommandReference::Figures::Component.new(page(words)).canvas.standalone

  def test_the_component_svg_is_well_formed_for_a_chain_a_command_and_a_hook
    ["intent end", "project list", "hook end"].each { |words| assert_equal "svg", REXML::Document.new(svg(words)).root.name, words }
  end

  def test_a_command_that_touches_no_database_says_so
    assert_includes svg("version"), "touches no database"
  end

  def test_a_database_lists_its_tables
    assert_includes svg("node add"), "work_graph.db"
    assert_includes svg("node add"), "nodes"
  end
end
