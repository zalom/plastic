# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_batch"
require_relative "../../../scripts/lib/plastic/commands/roadmap_add"
require_relative "../../../scripts/lib/plastic/commands/roadmap_start"

class RoadmapStartTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "start", *args, table: Plastic::CLI::TABLE)

  def setup
    super
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

    assert_equal 1, result.code
    assert_includes result.err, "no item zz on roadmap r1"
  end

  def test_a_second_start_exits_3
    call("r1", "a")

    result = call("r1", "a")

    assert_equal 3, result.code
  end

  def test_a_blocked_item_exits_3_with_no_intent_row
    plastic("roadmap", "add", "r1", "1", "b", "--title", "B", "--after", "a", table: Plastic::CLI::TABLE)

    result = call("r1", "b")

    assert_equal 3, result.code
    assert_nil item_row("b").intent_id
  end
end
