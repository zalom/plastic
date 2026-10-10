# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceWorkflowFigureTest < Minitest::Test
  include CommandReferenceHelper

  def figure(words, index = 0)
    command = page(words)
    CommandReference::Figures::Workflow.new(command, command.flows.fetch(index)).canvas
  end

  def test_the_workflow_drawing_is_at_most_760_wide
    CommandReferenceHelper.pages.each_value do |command|
      command.flows.each { |flow| assert_operator CommandReference::Figures::Workflow.new(command, flow).canvas.width, :<=, 760, command.words }
    end
  end

  def test_the_workflow_svg_is_well_formed
    assert_equal "svg", REXML::Document.new(figure("intent end").standalone).root.name
    assert_equal "svg", REXML::Document.new(figure("intent end", 1).standalone).root.name
  end

  def test_a_command_with_no_chain_draws_one_box_for_its_call
    command = page("project list")

    assert_equal "svg", REXML::Document.new(CommandReference::Figures::Call.new(command).canvas.standalone).root.name
  end
end
