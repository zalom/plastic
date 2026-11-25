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

  def rulings = store_graphs.retrieval.rulings("1").sort_by(&:id).map { |ruling| [ruling.id, ruling.text] }

  def test_a_ruling_reads_back_as_one_row
    open_intent

    result = call("1", "Flowbite styles every delivery")

    assert_call result, code: 0, err: "", out: ["D1: Flowbite styles every delivery", "next: plastic intent brief 1"]
    store_database = store_graphs.databases.fetch(:store)

    assert_equal 1, store_database.row("SELECT COUNT(*) AS n FROM rulings").fetch("n")
  end

  def test_a_text_that_begins_with_its_own_id_is_stored_and_printed_without_it
    open_intent

    result = call("1", "D1 Flowbite styles every delivery")

    assert_includes result.out, "D1: Flowbite styles every delivery\n"
    assert_equal ["Flowbite styles every delivery"], store_graphs.retrieval.rulings("1").map(&:text)
  end

  def test_two_rulings_read_d1_and_d2
    open_intent

    first = call("1", "Flowbite styles every delivery")
    second = call("1", "Direct mode only, never delegated")

    assert_equal ["D1: Flowbite", "D2: Direct"], [first, second].map { |result| result.out.split[0, 2].join(" ") }
  end

  def test_adds_writes_the_next_addition_of_the_decision
    open_intent
    call("1", "Flowbite styles every delivery")

    result = call("1", "Direct mode only", "--adds", "D1")

    assert_call result, code: 0, err: "", out: ["D1.1: Direct mode only", "next: plastic intent brief 1"]
  end

  def test_rewrites_replaces_the_text_and_says_which_additions_it_removed
    open_intent
    call("1", "Flowbite styles every delivery")
    call("1", "Direct mode only", "--adds", "D1")
    call("1", "No subagents", "--adds", "D1")

    result = call("1", "Flowbite styles every web application", "--rewrites", "D1")

    assert_call result, code: 0, err: "",
      out: ["D1: Flowbite styles every web application", "removed: the additions D1.1 and D1.2", "next: plastic intent brief 1"]
    assert_equal [["D1", "Flowbite styles every web application"]], rulings
  end

  def test_a_rewrite_of_a_decision_with_no_additions_names_none_removed
    open_intent
    call("1", "Flowbite styles every delivery")

    result = call("1", "Flowbite styles every web application", "--rewrites", "D1")

    assert_call result, code: 0, err: "", out: ["D1: Flowbite styles every web application", "next: plastic intent brief 1"]
  end

  def test_the_work_log_keeps_the_text_a_rewrite_replaced
    open_intent
    call("1", "Flowbite styles every delivery")
    call("1", "Flowbite styles every web application", "--rewrites", "D1")

    texts = store_graphs.retrieval.structure.work_log("1").select { |line| line.kind == "ruled" }.map(&:text)

    assert_equal ["D1: Flowbite styles every delivery", "D1: Flowbite styles every web application"], texts
  end

  def test_adds_or_rewrites_naming_a_missing_decision_exits_1_with_no_row_written
    open_intent

    results = [call("1", "Direct mode only", "--adds", "D9"), call("1", "Direct mode only", "--rewrites", "D9")]

    assert_equal [[1, ""], [1, ""]], results.map { |result| [result.code, result.out] }
    assert_equal ["no decision D9 in intent 1"] * 2, results.map { |result| result.err.lines.first.chomp.delete_prefix("plastic: ") }
    assert_empty rulings
  end

  def test_adds_or_rewrites_naming_an_addition_exits_2
    open_intent
    call("1", "Flowbite styles every delivery")
    call("1", "Direct mode only", "--adds", "D1")

    results = [call("1", "No subagents", "--adds", "D1.1"), call("1", "No subagents", "--rewrites", "D1.1")]

    assert_equal [2, 2], results.map(&:code)
    assert_includes results.first.err, "--adds and --rewrites name a whole decision, such as D1"
    assert_equal 2, rulings.size
  end

  def test_adds_and_rewrites_together_exit_2
    open_intent
    call("1", "Flowbite styles every delivery")

    result = call("1", "No subagents", "--adds", "D1", "--rewrites", "D1")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "--adds and --rewrites exclude each other"
  end

  def test_supersedes_is_no_option
    open_intent
    call("1", "Flowbite styles every delivery")

    result = call("1", "Direct mode only", "--supersedes", "D1")

    assert_equal 2, result.code
    assert_equal 1, rulings.size
  end
end
