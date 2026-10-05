# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyRoadmapsTest < Plastic::TestCase
  Parse = Plastic::Graph::Knowledge::Roadmap::Parse

  def roadmaps = Plastic::Graph::Knowledge::Legacy::Roadmaps.new

  def root = folder.path(".")

  def result(batches: [], edges: {}, log: [])
    items = [Parse::Item.new(item: "1", batch: nil, title: "First", status: nil), Parse::Item.new(item: "2", batch: nil, title: "Second", status: nil)]
    Parse::Result.new(title: "Plan", goal: "Ship", batches:, items:, edges:, log:, problems: [])
  end

  def test_the_roadmap_files_skip_the_savepoint_siblings_and_include_archived_ones
    %w[roadmaps/a.md roadmaps/a.savepoint.md roadmaps/archived/b.md].each { |path| write(path, "# R\n") }

    assert_equal %w[roadmaps/a.md roadmaps/archived/b.md], roadmaps.roadmap_files(root).map { |path| roadmaps.relative(root, path) }
  end

  def write_rows(parsed = result) = roadmaps.write_roadmap_rows(store_graphs, "plan", parsed, folder.path("missing"))

  def test_a_roadmap_with_no_batch_headings_gets_one_batch_named_after_it
    write_rows

    assert_equal [[1, "Plan"]], retrieval.batches("plan").map { |batch| [batch.position, batch.title] }
  end

  def test_a_roadmap_with_no_batch_headings_puts_every_item_in_its_one_batch
    write_rows

    assert_equal [%w[1 1], %w[2 1]], retrieval.roadmap_items("plan").map { |item| [item.item, item.batch.to_s] }
  end

  def test_the_header_is_written
    write_rows

    assert_equal %w[Plan Ship], retrieval.roadmap("plan").to_h.values_at(:title, :goal)
  end

  def test_the_edges_are_written
    write_rows(result(edges: { "2" => ["1"] }))

    assert_equal [%w[1 2]], retrieval.roadmap_edges("plan").map { |edge| [edge.from, edge.to] }
  end

  def test_an_item_keyed_by_an_intent_in_the_store_names_that_intent
    store_graphs.work.write_intent(title: "Alpha")
    roadmaps.write_roadmap_rows(store_graphs, "plan", result, folder.path("missing"))

    assert_equal ["1", nil], retrieval.roadmap_items("plan").map(&:intent_id)
  end

  def test_the_savepoint_sibling_lines_follow_the_roadmap_log
    write("roadmaps/plan.savepoint.md", "2026-10-02 Started   it\n\n")
    log = [Parse::LogLine.new(at: "2026-10-01", text: "Opened")]
    roadmaps.write_roadmap_rows(store_graphs, "plan", result(log:), folder.path("roadmaps/plan.savepoint.md"))

    assert_equal [%w[2026-10-01 Opened], ["2026-10-02", "Started it"]], retrieval.roadmap_log("plan").map { |line| [line.at, line.text] }
  end

  def test_migrating_counts_the_roadmaps_and_items_and_prints_the_file
    write("roadmaps/plan.md", "# Plan\n\n## Batches\n\n### Batch 1 — First\n- [ ] 7 Build it — queued\n")
    counts = Hash.new(0)
    roadmaps.migrate_roadmaps(store_graphs, root, roadmaps.parse(root), counts)

    assert_equal [1, 1], counts.values_at(:roadmaps, :roadmap_items)
    assert_equal ["Build it"], retrieval.roadmap_items("plan").map(&:title)
  end
end
