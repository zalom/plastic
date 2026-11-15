# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceCallFigureTest < Minitest::Test
  include CommandReferenceHelper

  def svg(words) = CommandReference::Figures::Call.new(page(words)).canvas.standalone

  def test_the_call_drawing_of_a_hook_and_a_no_workflow_command_parse
    ["hook end", "project list"].each { |words| assert_equal "svg", REXML::Document.new(svg(words)).root.name, words }
  end

  def test_the_call_drawing_of_a_command_with_no_workflow_says_so
    assert_includes svg("project list"), "ONE CALL, NO WORKFLOW"
  end
end
