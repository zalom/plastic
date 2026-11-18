# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/rule"

class IntentRuleCaseTest < Plastic::TestCase
  def test_a_ruling_on_a_missing_intent_exits_1_and_names_it
    assert_case line('intent rule 9 "Direct mode only"'), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class IntentRuleTest < Plastic::TestCase
  def call(*args) = plastic("intent", "rule", *args, table: Plastic::CLI::TABLE)

  def test_a_ruling_reads_back_as_one_row
    open_intent

    result = call("1", "Flowbite styles every delivery")

    assert_call result, code: 0, err: "", out: ["ruling: D1", "next: plastic intent brief 1"]
    store_database = store_graphs.databases.fetch(:store)

    assert_equal 1, store_database.row("SELECT COUNT(*) AS n FROM rulings").fetch("n")
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

    assert_equal [1, ""], [result.code, result.out]
    assert_includes result.err, "no ruling D9 in intent 1"
    assert_empty store_graphs.retrieval.rulings("1")
  end
end
