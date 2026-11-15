# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceEventRowFigureTest < Minitest::Test
  include CommandReferenceHelper

  FOLDER = "docs/reference/commands"

  def svg_of(words) = CommandReferenceHelper.files.fetch("#{FOLDER}/#{page(words).slug}/events.svg")

  def listed(words) = CommandReference::EventList.new(page(words)).events

  def test_the_condition_of_each_way_is_drawn_in_the_events_drawing
    words = REXML::Document.new(svg_of("intent end")).get_elements("//text").map(&:text).join(" ")
    ways = listed("intent end").filter_map(&:way).map { |way| way.split.first(8).join(" ") }

    assert_equal ways, ways.select { |way| words.include?(way) }
  end

  def test_the_solid_arrows_of_the_events_drawing_are_one_for_each_joined_event_after_the_first
    CommandReferenceHelper.pages.each_value do |each|
      svg = CommandReferenceHelper.files.fetch("#{FOLDER}/#{each.slug}/events.svg")

      assert_equal listed(each.words).drop(1).count(&:joined), svg.scan('class="wire"').size, each.words
    end
  end
end
