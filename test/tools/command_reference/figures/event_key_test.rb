# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceEventKeyFigureTest < Minitest::Test
  include CommandReferenceHelper

  FOLDER = "docs/reference/commands"

  def keys = CommandReferenceHelper.files.select { |path, _| path.end_with?("/events.svg") }.transform_values { |svg| labels(svg) }

  def labels(svg) = REXML::Document.new(svg).get_elements("//text").select { |each| each.attributes["class"] == "k" }

  def gaps(labels)
    labels.each_cons(2).map { |now, after| after.attributes["x"].to_i - 20 - now.attributes["x"].to_i - CommandReference::Figures::Glyphs.width(now.text.to_s).ceil }
  end

  def test_the_gaps_between_the_entries_of_every_key_are_equal
    keys.each { |path, labels| assert_equal 1, gaps(labels).uniq.size, path }
  end

  def test_a_narrow_label_measures_less_than_a_wide_one_of_the_same_length
    assert_operator CommandReference::Figures::Glyphs.width("illi"), :<, CommandReference::Figures::Glyphs.width("mwmw")
  end

  def test_a_longer_label_measures_more_than_a_shorter_one_with_the_same_letters
    assert_operator CommandReference::Figures::Glyphs.width("Ends"), :<, CommandReference::Figures::Glyphs.width("Ends and more")
  end
end
