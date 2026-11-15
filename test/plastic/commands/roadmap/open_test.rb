# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/roadmap/batch"
require_relative "../../../../lib/plastic/commands/roadmap/add"
require_relative "../../../../lib/plastic/commands/roadmap/open"

class RoadmapOpenCaseTest < Plastic::TestCase
  def test_opening_a_ready_item_of_a_legacy_roadmap_starts_its_intent
    legacy_roadmap
    ran("roadmap next make-it-useful --batch 1")

    assert_case line("roadmap open make-it-useful 2"), code: 0, out: ["intent: 2"]
  end

  def test_opening_an_item_prints_its_intent_and_offers_the_brief
    shop_guest

    assert_case line("roadmap open shop guest"), code: 0, out: ["intent: 1", "next: plastic intent brief 1"]
  end
end

class RoadmapOpenTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "open", *args, table: Plastic::CLI::TABLE)

  def setup
    super
    plastic("roadmap", "new", "r1", table: Plastic::CLI::TABLE)
    plastic("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "Batch goal", "--done", "batch done",
      table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "a", "--title", "A", "--goal", "Item goal", "--done", "item done",
      table: Plastic::CLI::TABLE)
  end

  def item_row(item) = store_graphs.retrieval.roadmap_items("r1").find { |row| row.item == item }

  def spec_of(item) = store_graphs.retrieval.documents(item.intent_id).find { |candidate| candidate.path == "spec.md" }

  def test_spec_holds_both_headings
    call("r1", "a")

    document = spec_of(item_row("a"))

    assert_includes document.body, "## Goal"
    assert_includes document.body, "## Done criteria"
  end

  def test_spec_holds_the_batch_and_item_goal
    call("r1", "a")

    document = spec_of(item_row("a"))

    assert_includes document.body, "Batch goal"
    assert_includes document.body, "Item goal"
  end

  def test_spec_holds_the_batch_and_item_done_bullets
    call("r1", "a")

    document = spec_of(item_row("a"))

    assert_includes document.body, "- [ ] batch done"
    assert_includes document.body, "- [ ] item done"
  end

  def test_an_unknown_item_exits_1_and_names_it
    result = call("r1", "zz")

    assert_equal [1, ""], [result.code, result.out]
    assert_equal "plastic: no item zz on roadmap r1\n", result.err
  end

  def test_a_second_open_exits_3
    call("r1", "a")

    result = call("r1", "a")

    assert_equal 3, result.code
  end

  def test_a_blocked_item_exits_3_with_no_intent_row
    plastic("roadmap", "add", "r1", "1", "b", "--title", "B", "--needs", "a", table: Plastic::CLI::TABLE)

    result = call("r1", "b")

    assert_call result, code: 3, err: "plastic: refused, item b is blocked, not ready\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n"
    assert_nil item_row("b").intent_id
  end
end
