# frozen_string_literal: true

require_relative "../../../test_helper"

class RoadmapShowCaseTest < Plastic::TestCase
  def test_showing_one_batch_prints_each_item_ready_or_blocked_and_offers_the_next_item
    shop_guest
    ran('roadmap add shop 1 pay --title "Charge on confirm" --needs guest')

    assert_case line("roadmap show shop --batch 1"), code: 0, out: ["batch 1: Blockers - guest checkout is safe",
      "item guest: Lock down guest orders - ready, needs nothing", "item pay: Charge on confirm - blocked, needs guest",
      "next: plastic roadmap next shop"]
  end
end

class RoadmapShowTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def test_show_prints_the_batch_its_criteria_and_its_items
    cli("roadmap", "new", "r1")
    cli("roadmap", "batch", "r1", "1", "--title", "Wave one", "--goal", "Ship it", "--done", "a done", "--done", "b done")
    cli("roadmap", "add", "r1", "1", "a", "--title", "A")

    result = cli("roadmap", "show", "r1")

    assert_call result, code: 0, out: ["batch 1: Wave one - Ship it\n  done: a done\n  done: b done\n",
      "item a: A - ", "needs nothing", "next: plastic roadmap next r1"]
  end

  def test_show_on_a_missing_roadmap_names_it
    result = cli("roadmap", "show", "r9")

    assert_call result, code: 1, out: "", err: "plastic: no roadmap r9\n"
  end

  def test_a_hand_edited_roadmap_file_survives_the_call_and_no_row_is_added
    cli("roadmap", "new", "r1")
    cli("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d")
    path = store_path("roadmaps/r1.md")
    File.write(path, "hand edit\n")
    before = run_count

    result = cli("roadmap", "show", "r1")

    assert_equal "hand edit\n", File.read(path)
    assert_equal before, run_count
    assert_equal "", result.out.lines.grep(/^wrote:/).join
  end

  def run_count = store_graphs.databases.fetch(:local).row("SELECT count(*) AS n FROM command_runs").fetch("n")
end
