# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderRoadmapFileTest < Plastic::TestCase
  RoadmapFile = Plastic::Graph::Knowledge::Reader::RoadmapFile
  FORM = "<!-- plastic roadmap form 2 -->"
  TRICKY = "# Not a title\n## Batch 9\n- [x] 3 Other \\ back — done\n  item: fake"

  def work = store_graphs.databases.fetch(:work)

  def seed(title: TRICKY, item_title: "Hello — world — ready", goal: "Line one\nLine two")
    work.transaction do |batch|
      batch.put(:roadmaps, { slug: "plan", title:, goal:, opened_at: STAMP, updated_at: STAMP })
      batch.put(:batches, { roadmap: "plan", position: 1, title:, goal:, done: "first\nsecond", updated_at: STAMP })
      batch.put(:roadmap_items, { roadmap: "plan", item: "1", batch: 1, position: 1, title: item_title, goal:, done: "d", mark: "dropped", updated_at: STAMP })
      batch.put(:roadmap_items, { roadmap: "plan", item: "2", batch: 1, position: 2, title: "Second", updated_at: STAMP })
      batch.put(:roadmap_edges, { roadmap: "plan", from: "1", to: "2", kind: "after" })
      batch.put(:roadmap_log, { roadmap: "plan", position: 1, at: STAMP, text: TRICKY, session_id: "s1" })
    end
  end

  def printed = Plastic::Graph::RoadmapPrint.new(retrieval, "plan").text

  def clear
    work.transaction do |batch|
      %i[roadmaps batches roadmap_items roadmap_edges roadmap_log].each do |table|
        batch.remove(table, **{ ((table == :roadmaps) ? :slug : :roadmap) => "plan" })
      end
    end
  end

  def read(text) = work.transaction { |batch| RoadmapFile.new("plan", text).apply(batch) }

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

  def test_a_file_in_another_form_is_refused_as_an_older_form
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", "# Plan\n\n## Goal\n\nShip\n") }

    assert_includes error.message, "older form"
  end

  def test_a_file_with_an_unknown_form_line_is_refused_as_an_older_form
    error = assert_raises(Plastic::Invalid) { RoadmapFile.new("plan", "<!-- plastic roadmap form 9 -->\n") }

    assert_includes error.message, "older form"
  end

  def test_form_question_tells_the_two_apart
    assert_equal [true, false], [RoadmapFile.form?("#{FORM}\n"), RoadmapFile.form?("# Plan\n")]
  end
end
