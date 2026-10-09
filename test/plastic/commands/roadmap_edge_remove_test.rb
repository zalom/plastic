# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_batch"
require_relative "../../../scripts/lib/plastic/commands/roadmap_add"
require_relative "../../../scripts/lib/plastic/commands/roadmap_edge_remove"

class RoadmapEdgeRemoveTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "edge", "remove", *args, table: Plastic::CLI::TABLE)

  def setup
    super
    plastic("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d", table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "a", "--title", "A", table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "b", "--title", "B", table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "c", "--title", "C", "--after", "a", "--after", "b", table: Plastic::CLI::TABLE)
  end

  def edges = store_graphs.retrieval.roadmap_edges("r1")

  def test_the_named_edge_goes_and_the_other_stays
    result = call("r1", "a", "c")

    assert_equal 0, result.code
    assert_equal [%w[b c]], edges.map { |edge| [edge.from, edge.to] }
  end

  def test_a_missing_edge_exits_1
    call("r1", "a", "c")

    result = call("r1", "a", "c")

    assert_equal 1, result.code
  end

  def test_a_failed_removal_succeeds_once_the_edge_exists
    call("r1", "a", "d")
    plastic("roadmap", "add", "r1", "1", "d", "--title", "D", "--after", "a", table: Plastic::CLI::TABLE)

    result = call("r1", "a", "d")

    assert_call result, code: 0,
      out: "edge: a to d removed\nwrote:  1 routine run in local.db\n        1 roadmap edge in work_graph.db\nfiles:  roadmaps/r1.md\n\nnext: plastic roadmap show r1 --project global\nbecause: edge a to d is gone\n"
    refute_includes edges.map { |edge| [edge.from, edge.to] }, %w[a d]
  end

  def test_preview_matches_apply_on_an_identical_home
    twin = twin_run("roadmap", "edge", "remove", "r1", "a", "c") do |home|
      seed_roadmap(home, "a", "b")
      call_in(home, "roadmap", "add", "r1", "1", "c", "--title", "C", "--after", "a", "--after", "b")
    end

    assert_preview_matches_apply(twin)
    assert_equal 0, twin.previewed.code
  end
end
