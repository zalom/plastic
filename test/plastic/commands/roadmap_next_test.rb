# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_batch"
require_relative "../../../scripts/lib/plastic/commands/roadmap_add"
require_relative "../../../scripts/lib/plastic/commands/roadmap_next"

class RoadmapNextTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "next", *args, table: Plastic::CLI::TABLE)

  def setup
    super
    plastic("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d", table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "a", "--title", "A", table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "b", "--title", "B", "--needs", "a", table: Plastic::CLI::TABLE)
  end

  def mark_done(item)
    intent = open_intent("Item #{item}")
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :id", id: intent.intent_id)
      batch.write(:roadmap_items, "UPDATE roadmap_items SET intent_id = :id WHERE roadmap = 'r1' AND item = :item",
        id: intent.intent_id, item:)
    end
  end

  def test_b_is_not_printed_and_is_named_blocked_while_a_is_open
    result = call("r1")

    refute_includes result.out, "a: "
    assert_includes result.out, "b: blocked"
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
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.put(:roadmap_edges, { roadmap: "r1", from: "b", to: "a", kind: "after" }, statement: :insert)
    end

    result = call("r1")

    assert_equal 0, result.code
    assert_includes result.out, "a: blocked"
    assert_includes result.out, "b: blocked"
  end
end
