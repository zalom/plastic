# frozen_string_literal: true

require_relative "../../test_helper"

class RoadmapDropTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def setup
    super
    cli("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d")
    cli("roadmap", "add", "r1", "1", "a", "--title", "A")
  end

  def test_dropping_an_item_says_so_and_offers_the_next_items
    result = cli("roadmap", "drop", "r1", "a")

    assert_call result, code: 0,
      out: "dropped: a\nwrote:  1 routine run in local.db\n        1 item in work_graph.db\nfiles:  roadmaps/r1.md\n\nnext: plastic roadmap next r1 --project global\nbecause: item a no longer blocks its successors\n"
  end

  def test_dropping_on_a_missing_roadmap_names_it
    result = cli("roadmap", "drop", "r9", "a")

    assert_call result, code: 1, out: RUN_ROW, err: "plastic: code_drop_roadmap_item, gate: no roadmap r9\n"
  end

  def test_dropping_a_missing_item_names_it
    result = cli("roadmap", "drop", "r1", "z")

    assert_call result, code: 1, out: RUN_ROW, err: "plastic: code_drop_roadmap_item, gate: no item z on roadmap r1\n"
  end

  def test_preview_matches_apply_on_an_identical_home
    twin = twin_run("roadmap", "drop", "r1", "a") { |home| seed_roadmap(home, "a", "b") }

    assert_preview_matches_apply(twin)
    assert_equal 0, twin.previewed.code
  end
end
