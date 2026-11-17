# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/roadmap/batch"
require_relative "../../../../lib/plastic/commands/roadmap/add"
require_relative "../../../../lib/plastic/commands/roadmap/next"

class RoadmapNextCaseTest < Plastic::TestCase
  def test_the_first_batch_of_a_legacy_roadmap_has_two_ready_items
    legacy_roadmap

    assert_case line("roadmap next make-it-useful --batch 1"), code: 0, out: ["2: ready", "3: ready"]
  end

  def test_a_batch_with_no_items_has_nothing_next_and_offers_the_roadmap
    shop_batch

    assert_case line("roadmap next shop"), code: 0, out: ["next: plastic roadmap show shop"]
  end

  def test_the_next_item_of_a_roadmap_that_does_not_exist_exits_1_and_names_it
    assert_case line("roadmap next shop"), code: 1, out: "", err: ["no roadmap shop"]
  end
end

class RoadmapNextTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "next", *args, table: Plastic::CLI::TABLE)

  def setup
    super
    plastic("roadmap", "new", "r1", table: Plastic::CLI::TABLE)
    plastic("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d", table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "a", "--title", "A", table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "b", "--title", "B", "--needs", "a", table: Plastic::CLI::TABLE)
  end

  def mark_done(item)
    intent = open_intent("Item #{item}")
    store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :id", id: intent.intent_id) }
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.write(:roadmap_items, "UPDATE roadmap_items SET intent_id = :id WHERE roadmap = 'r1' AND item = :item",
        id: intent.intent_id, item:)
    end
  end

  def test_b_is_not_printed_and_is_named_blocked_while_a_is_open
    result = call("r1")

    refute_includes result.out, "a: "
    assert_call result, code: 0, err: "", out: ["b: blocked", "next: plastic roadmap open r1 a"]
  end

  def test_b_is_printed_once_a_is_done
    mark_done("a")

    result = call("r1")

    assert_includes result.out, "b: ready"
  end

  def test_b_is_ready_once_a_is_dropped
    plastic("roadmap", "drop", "r1", "a", table: Plastic::CLI::TABLE)

    result = call("r1")

    assert_includes result.out, "b: ready"
    assert_equal 0, result.code
    assert_equal "", result.err
  end

  def test_an_imported_cycle_is_blocked_without_recursing
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.put(:roadmap_edges, { roadmap: "r1", from: "b", to: "a", kind: "after" }, statement: :insert)
    end

    result = call("r1")

    assert_equal 0, result.code
    assert_includes result.out, "a: blocked"
    assert_includes result.out, "b: blocked"
  end
end
