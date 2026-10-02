# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_rule"

class IntentRuleTest < Plastic::TestCase
  def call(*args) = plastic("intent", "rule", *args, table: Plastic::CLI::TABLE)

  def test_a_ruling_reads_back_and_one_change_row_exists
    open_intent

    result = call("1", "Flowbite styles every delivery")

    assert_includes result.out, "ruling: D1"
    knowledge = store_graphs.databases.fetch(:knowledge)

    assert_equal 1, knowledge.row("SELECT COUNT(*) AS n FROM changes WHERE \"table\" = 'rulings'").fetch("n")
  end

  def test_two_rulings_read_d1_and_d2
    open_intent

    first = call("1", "Flowbite styles every delivery")
    second = call("1", "Direct mode only, never delegated")

    assert_includes first.out, "ruling: D1"
    assert_includes second.out, "ruling: D2"
  end

  def test_supersedes_writes_a_link_from_d2_to_d1
    open_intent
    call("1", "Flowbite styles every delivery")

    call("1", "Flowbite styles every delivery, direct mode only", "--supersedes", "D1")

    links = store_graphs.retrieval.links("1/D1")

    assert_equal 1, links.size
    assert_equal "1/D2", links.first.from_ref
    assert_equal "supersedes", links.first.kind
  end

  def test_supersedes_naming_a_missing_ruling_exits_1_with_no_row_written
    open_intent

    result = call("1", "Flowbite styles every delivery", "--supersedes", "D9")

    assert_equal 1, result.code
    assert_empty store_graphs.retrieval.rulings("1")
  end
end
