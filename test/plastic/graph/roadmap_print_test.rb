# frozen_string_literal: true

require_relative "../../test_helper"

class GraphRoadmapPrintTest < Plastic::TestCase
  Parse = Plastic::Graph::Knowledge::Roadmap::Parse

  def parsed(goal: "Ship", edges: { "2" => ["1"] })
    items = [Parse::Item.new(item: "1", batch: nil, title: "First", status: nil), Parse::Item.new(item: "2", batch: nil, title: "Second", status: nil)]
    Parse::Result.new(title: "Plan", goal:, batches: [], items:, edges:, log: [Parse::LogLine.new(at: "2026-10-01", text: "Opened")], problems: [])
  end

  def printed(**options)
    Plastic::Graph::Knowledge::Legacy::Roadmaps.new.write_roadmap_rows(store_graphs, "plan", parsed(**options), folder.path("missing"))
    Plastic::Graph::RoadmapPrint.new(retrieval, "plan").text
  end

  def test_the_file_starts_with_the_title_and_the_goal
    assert_equal ["# Plan", "", "## Goal", "", "Ship", ""], printed.lines.first(6).map(&:chomp)
  end

  def test_a_roadmap_without_a_goal_prints_no_goal_section
    refute_includes printed(goal: nil), "## Goal"
  end

  def test_the_batch_lists_each_item_with_its_state
    assert_includes printed, "- [ ] 1 First — "
  end

  def test_a_delivered_item_is_checked
    printed
    store_graphs.databases[:work].transaction do |batch|
      batch.put(:roadmap_items, { roadmap: "plan", item: "1", batch: 1, position: 1, title: "First", mark: "delivered", updated_at: STAMP })
    end

    assert_includes Plastic::Graph::RoadmapPrint.new(retrieval, "plan").text, "- [x] 1 First — done"
  end

  def test_the_graph_names_what_each_item_needs
    assert_includes printed, "- 1 needs nothing\n- 2 needs 1\n"
  end

  def test_the_log_ends_the_file
    assert_match(/## Log\n\n- .*Opened\n\z/, printed)
  end

  def test_the_prints_wrap_the_text_in_a_work_file
    printed
    print = Plastic::Graph::Prints.roadmap(retrieval, "plan")

    assert_equal ["roadmaps/plan.md", :work], [print.path, print.database]
  end
end
