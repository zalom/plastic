# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceOverviewFigureTest < Minitest::Test
  include CommandReferenceHelper

  FOLDER = "docs/reference/commands"
  FLOW_TAGS = ["tag tag-code", "tag tag-agent"].freeze
  END_TAGS = ["tag tag-end", "tag tag-handoff"].freeze
  UNREACHABLE = ["completion records are ready", "architecture map are recorded", "left running"].freeze

  def texts(svg) = REXML::Document.new(svg).get_elements("//text").map { |each| [each.attributes["class"], each.text.to_s] }

  def workflow_texts(each) = texts(CommandReferenceHelper.files.fetch("#{FOLDER}/#{each.slug}/workflows.svg"))

  def several_flows = CommandReferenceHelper.pages.values.select { |each| each.flows.size > 1 }

  def drawn_words(each) = workflow_texts(each).map(&:last).join(" ")

  def test_the_endings_that_no_call_can_reach_are_not_drawn_in_the_workflows_of_intent_end
    assert_empty UNREACHABLE.select { |text| drawn_words(page("intent end")).include?(text) }
  end

  def test_the_ways_of_intent_end_come_in_the_order_of_the_delivery
    words = drawn_words(page("intent end"))
    at = ["still needs records", "not verified yet", "in place"].map { |text| words.index(text) }

    assert_equal at.compact.sort, at
  end

  def test_the_three_ways_of_intent_end_are_all_drawn
    words = drawn_words(page("intent end"))

    assert_equal [true, true, true], ["still needs records", "not verified yet", "in place"].map { |text| words.include?(text) }
  end

  def test_every_workflow_of_a_page_is_drawn_once
    several_flows.each do |each|
      drawn = workflow_texts(each).count { |css, _| FLOW_TAGS.any? { |tag| css.start_with?(tag) } }

      assert_equal each.flows.size, drawn, each.words
    end
  end

  def test_the_drawing_holds_a_gate_card_for_every_workflow_with_a_gate
    several_flows.each do |each|
      expected = each.flows.count { |flow| CommandReference::FlowStops.new(flow).gates.any? }
      found = workflow_texts(each).count { |_css, words| words.start_with?("A check fails", "The step belongs to") }

      assert_equal expected, found, each.words
    end
  end

  def test_the_drawing_holds_every_ending_of_every_workflow
    several_flows.each do |each|
      expected = each.flows.sum { |flow| CommandReference::FlowStops.new(flow).closing.size }
      found = workflow_texts(each).count { |css, _| END_TAGS.include?(css) }

      assert_equal expected, found, each.words
    end
  end

  def test_the_workflows_of_intent_end_hold_a_box_for_each_workflow
    drawn = workflow_texts(page("intent end")).count { |css, _| FLOW_TAGS.any? { |tag| css.start_with?(tag) } }

    assert_equal page("intent end").flows.size, drawn
  end

  def test_the_workflows_of_intent_end_hold_the_summary_of_the_last_workflow
    assert_includes drawn_words(page("intent end")), "Closes the intent and releases its lock."
  end

  def test_the_workflows_of_intent_end_hold_the_text_of_a_branch
    assert_includes drawn_words(page("intent end")), "the merge of the work is not verified yet"
  end
end
