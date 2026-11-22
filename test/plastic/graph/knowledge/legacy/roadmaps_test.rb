# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyRoadmapsTest < Plastic::TestCase
  Parse = Plastic::Graph::Knowledge::Roadmap::Parse

  Legacy = Plastic::Graph::Knowledge::Legacy

  def roadmaps = Legacy::Roadmaps.new(root)

  def rows(parsed, savepoint = folder.path("missing")) = Legacy::RoadmapRows.new(store_graphs, "plan", parsed).call(savepoint)

  def root = folder.path(".")

  def result(batches: [], edges: {}, log: [])
    items = [Parse::Item.new(item: "1", batch: nil, title: "First", status: nil), Parse::Item.new(item: "2", batch: nil, title: "Second", status: nil)]
    Parse::Result.new(title: "Plan", goal: "Ship", batches:, items:, edges:, log:, problems: [])
  end

  def test_the_roadmap_files_skip_the_savepoint_siblings_and_include_archived_ones
    %w[roadmaps/a.md roadmaps/a.savepoint.md roadmaps/archived/b.md].each { |path| write(path, "# R\n") }

    assert_equal %w[roadmaps/a.md roadmaps/archived/b.md], roadmaps.files.map { |path| roadmaps.relative(path) }
  end

  def write_rows(parsed = result) = rows(parsed)

  def test_a_roadmap_with_no_batch_headings_gets_one_batch_named_after_it
    write_rows

    assert_equal [[1, "Plan"]], retrieval.roadmaps.batches("plan").map { |batch| [batch.position, batch.title] }
  end

  def test_a_roadmap_with_no_batch_headings_puts_every_item_in_its_one_batch
    write_rows

    assert_equal [%w[1 1], %w[2 1]], retrieval.roadmaps.items("plan").map { |item| [item.item, item.batch.to_s] }
  end

  def test_the_header_is_written
    write_rows

    assert_equal %w[Plan Ship], retrieval.roadmaps.find("plan").to_h.values_at(:title, :goal)
  end

  def test_the_edges_are_written
    write_rows(result(edges: { "2" => ["1"] }))

    assert_equal [%w[1 2]], retrieval.roadmaps.edges("plan").map { |edge| [edge.from, edge.to] }
  end

  def test_an_item_keyed_by_an_intent_in_the_store_names_that_intent
    store_graphs.work.write_intent(title: "Alpha")
    rows(result)

    assert_equal ["1", nil], retrieval.roadmaps.items("plan").map(&:intent_id)
  end

  def test_the_savepoint_sibling_lines_follow_the_roadmap_log
    write("roadmaps/plan.savepoint.md", "2026-10-02 Started   it\n\n")
    log = [Parse::LogLine.new(at: "2026-10-01", text: "Opened")]
    rows(result(log:), folder.path("roadmaps/plan.savepoint.md"))

    assert_equal [%w[2026-10-01 Opened], ["2026-10-02", "Started it"]], retrieval.roadmaps.log("plan").map { |line| [line.at, line.text] }
  end

  def savepoint_rows(line)
    write("roadmaps/plan.savepoint.md", "#{line} Started\n")
    rows(result, folder.path("roadmaps/plan.savepoint.md"))
  end

  def test_a_savepoint_line_with_an_offset_reaches_the_roadmap_log_in_utc
    savepoint_rows("2026-08-01T10:00:00+02:00")

    assert_equal ["2026-08-01T08:00:00Z"], retrieval.roadmaps.log("plan").map(&:at)
  end

  def test_a_savepoint_line_with_an_impossible_time_is_refused_and_writes_no_roadmap_log_row
    error = assert_raises(Plastic::Invalid) { savepoint_rows("2026-08-01T25:00:00+02:00") }

    assert_equal "2026-08-01T25:00:00+02:00 is not a time", error.message
    assert_empty retrieval.roadmaps.log("plan")
  end
end
