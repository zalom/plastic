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

class KnowledgeReaderRoadmapFileDoneTest < Plastic::TestCase
  RoadmapFile = Plastic::Graph::Knowledge::Reader::RoadmapFile

  def work = store_graphs.databases.fetch(:store)

  def seed
    work.transaction do |batch|
      batch.put(:roadmaps, { slug: "plan", title: "Plan", opened_at: STAMP, updated_at: STAMP })
      batch.put(:batches, { roadmap: "plan", position: 1, title: "One", done: "", updated_at: STAMP })
      batch.put(:roadmap_items, { roadmap: "plan", item: "1", batch: 1, position: 1, title: "First", done: "", updated_at: STAMP })
    end
  end

  def reread
    text = Plastic::Graph::RoadmapPrint.new(retrieval, "plan").text
    work.transaction do |batch|
      %i[roadmaps batches roadmap_items].each { |table| batch.remove(table, **{ ((table == :roadmaps) ? :slug : :roadmap) => "plan" }) }
    end
    work.transaction { |batch| RoadmapFile.new("plan", text, clock: FixedClock::CLOCK).apply(batch) }
  end

  def test_an_item_with_no_done_lines_reads_back_with_the_empty_done_the_writer_stores
    seed
    reread

    assert_equal "", retrieval.roadmap_items("plan").first.done
  end

  def test_a_batch_with_no_done_lines_reads_back_with_the_empty_done_the_writer_stores
    seed
    reread

    assert_equal "", retrieval.batches("plan").first.done
  end
end

class KnowledgeReaderRoadmapFileRefusedTest < Plastic::TestCase
  include RoadmapFileHelper

  def test_a_file_in_another_form_is_refused_as_an_older_form
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", "# Plan\n\n## Goal\n\nShip\n", clock: FixedClock::CLOCK) }

    assert_includes error.message, "older form"
  end

  def test_a_file_with_an_unknown_form_line_is_refused_as_an_older_form
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", "<!-- plastic roadmap form 9 -->\n", clock: FixedClock::CLOCK) }

    assert_includes error.message, "older form"
  end

  def test_a_position_that_is_not_a_number_is_refused_naming_the_field
    seed
    error = assert_raises(Plastic::Invalid) { read(printed.sub("  position: 1", "  position: first")) }

    assert_equal "roadmaps/plan.md holds a position that is not a number", error.message
  end

  def test_a_head_with_no_title_is_refused_naming_the_missing_field
    seed
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", printed.sub(/^title: .*\n/, ""), clock: FixedClock::CLOCK) }

    assert_equal "roadmaps/plan.md has a head record with no title", error.message
  end

  def test_an_item_with_no_position_is_refused_naming_an_item
    seed
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", printed.sub("  position: 1\n  title: Hello — world — ready", "  title: Hello"), clock: FixedClock::CLOCK) }

    assert_equal "roadmaps/plan.md has an item record with no position", error.message
  end

  def test_an_edge_with_no_kind_is_refused_naming_an_edge
    seed
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", printed.sub("  kind: after\n", ""), clock: FixedClock::CLOCK) }

    assert_equal "roadmaps/plan.md has an edge record with no kind", error.message
  end

  def test_a_log_line_with_no_text_is_refused_naming_a_log_line
    seed
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", printed.sub(/^  text: .*\n?\z/, ""), clock: FixedClock::CLOCK) }

    assert_equal "roadmaps/plan.md has a log line record with no text", error.message
  end

  def test_form_question_tells_the_two_apart
    assert_equal [true, false], [RoadmapFile.form?("#{FORM}\n"), RoadmapFile.form?("# Plan\n")]
  end
end
