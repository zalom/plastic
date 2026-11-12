# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceWorkflowsFigureTest < Minitest::Test
  include CommandReferenceHelper

  def figure(words) = CommandReference::Figures::Workflows.new(page(words)).canvas

  def test_the_workflows_of_intent_end_are_shorter_than_400_pixels
    assert_operator figure("intent end").height, :<, 400
  end

  def test_the_workflows_svg_is_well_formed_for_a_routine_a_command_and_a_hook
    ["intent end", "project list", "hook end"].each do |words|
      assert_equal "svg", REXML::Document.new(figure(words).standalone).root.name, words
    end
  end

  def test_the_workflows_svg_names_each_workflow
    assert_includes figure("intent end").standalone, "Prepare"
  end

  def test_the_workflows_svg_is_titled_with_workflow_words
    assert_includes figure("intent end").standalone, "<title>The workflows of plastic intent end</title>"
  end

  def test_the_workflows_svg_holds_no_timestamp_or_absolute_path
    refute_match(%r{20\d\d-\d\d-\d\d|/Users/}, figure("intent end").standalone)
  end
end
