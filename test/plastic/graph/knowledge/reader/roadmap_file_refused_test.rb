# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderRoadmapFileRefusedTest < Plastic::TestCase
  include RoadmapFileHelper

  def test_a_file_in_another_form_is_refused_as_an_older_form
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", "# Plan\n\n## Goal\n\nShip\n") }

    assert_includes error.message, "older form"
  end

  def test_a_file_with_an_unknown_form_line_is_refused_as_an_older_form
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", "<!-- plastic roadmap form 9 -->\n") }

    assert_includes error.message, "older form"
  end

  def test_a_position_that_is_not_a_number_is_refused_naming_the_field
    seed
    error = assert_raises(Plastic::Invalid) { read(printed.sub("  position: 1", "  position: first")) }

    assert_equal "roadmaps/plan.md holds a position that is not a number", error.message
  end

  def test_a_head_with_no_title_is_refused_naming_the_missing_field
    seed
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", printed.sub(/^title: .*\n/, "")) }

    assert_equal "roadmaps/plan.md has a head record with no title", error.message
  end

  def test_an_item_with_no_position_is_refused_naming_an_item
    seed
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", printed.sub("  position: 1\n  title: Hello — world — ready", "  title: Hello")) }

    assert_equal "roadmaps/plan.md has an item record with no position", error.message
  end

  def test_an_edge_with_no_kind_is_refused_naming_an_edge
    seed
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", printed.sub("  kind: after\n", "")) }

    assert_equal "roadmaps/plan.md has an edge record with no kind", error.message
  end

  def test_a_log_line_with_no_text_is_refused_naming_a_log_line
    seed
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", printed.sub(/^  text: .*\n?\z/, "")) }

    assert_equal "roadmaps/plan.md has a log line record with no text", error.message
  end

  def test_form_question_tells_the_two_apart
    assert_equal [true, false], [RoadmapFile.form?("#{FORM}\n"), RoadmapFile.form?("# Plan\n")]
  end
end
