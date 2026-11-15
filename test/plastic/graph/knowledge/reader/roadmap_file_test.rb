# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderRoadmapFileTest < Plastic::TestCase
  include RoadmapFileHelper

  def test_the_print_starts_with_the_form_line
    seed

    assert_equal FORM, printed.lines.first.chomp
  end

  def test_print_read_print_gives_the_same_bytes
    seed
    first = printed
    clear
    read(first)

    assert_equal first, printed
  end

  def test_text_that_looks_like_a_heading_an_item_line_or_a_state_word_reads_back_whole
    seed
    text = printed
    clear
    read(text)

    assert_equal [TRICKY, "Line one\nLine two"], [retrieval.roadmap("plan").title, retrieval.roadmap("plan").goal]
  end

  def test_a_done_note_and_a_log_line_that_look_like_markup_read_back_whole
    seed
    text = printed
    clear
    read(text)

    assert_equal ["first\nsecond", [TRICKY]], [retrieval.batches("plan").first.done, retrieval.roadmap_log("plan").map(&:text)]
  end

  def test_a_title_with_the_dash_separator_reads_back_whole
    seed
    first = printed
    clear
    read(first)

    assert_equal ["Hello — world — ready", "dropped"], retrieval.roadmap_items("plan").first.to_h.values_at(:title, :mark)
  end

  def test_the_edges_and_the_session_of_a_log_line_come_back
    seed
    text = printed
    clear
    read(text)

    assert_equal [%w[1 2 after], ["s1"]], [retrieval.roadmap_edges("plan").map { |edge| [edge.from, edge.to, edge.kind] }.first, retrieval.roadmap_log("plan").map(&:session_id)]
  end

  def test_the_reader_stamps_the_update_time_and_the_origin
    seed
    text = printed
    clear
    read(text)

    assert_equal [origin, true], [retrieval.roadmap("plan").origin_id, !retrieval.roadmap("plan").updated_at.nil?]
  end

  def test_an_item_with_no_title_reads_back_as_an_item_with_no_title
    seed(item_title: nil)
    text = printed
    clear
    read(text)

    assert_equal [nil, "Second"], retrieval.roadmap_items("plan").map(&:title)
  end

  def test_spaces_at_the_end_of_a_value_read_back_as_the_rows_hold_them
    seed(item_title: "Item one  ", goal: "  spaced  ")
    text = printed
    clear
    read(text)

    assert_equal [["Item one  ", "  spaced  "], "plan"], [retrieval.roadmap_items("plan").first.to_h.values_at(:title, :goal), retrieval.roadmap("plan").slug]
  end

  def test_a_value_left_out_prints_its_label_with_no_space_after_it
    seed(item_title: nil)

    assert_includes printed.lines(chomp: true), "  title:"
  end
end
