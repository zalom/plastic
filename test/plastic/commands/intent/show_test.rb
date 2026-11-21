# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/show"
require_relative "../../../../lib/plastic/commands/intent/rule"

class IntentShowCaseTest < Plastic::TestCase
  def test_showing_an_intent_prints_its_criteria_ruling_node_and_savepoint
    alpha_specified
    ran('intent rule 1 "ship the CLI first"', "node add 1 Build --criterion tests-pass")

    assert_case line("intent show 1"), code: 0, out: ["intent: 1 Alpha (future)", "criteria: 1", "ruling: D1 ship the CLI first",
      "node: n1 open Build", "Opened: Alpha", "next: plastic intent brief 1"]
  end

  def test_showing_a_missing_intent_exits_1_and_names_it
    assert_case line("intent show 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class IntentShowTest < Plastic::TestCase
  def call(*args) = plastic("intent", "show", *args, table: Plastic::CLI::TABLE)

  def test_unknown_id_exits_1
    result = call("9")

    assert_equal 1, result.code
  end

  def test_shows_the_intent_and_its_criteria_count
    intent = open_intent

    result = call(intent.intent_id)

    assert_call result, code: 0, err: "", out: ["intent: #{intent.intent_id} Alpha (open)", "criteria: 0", "Opened: Alpha"]
  end

  def test_shows_a_ruling_and_the_last_log_lines
    intent = open_intent
    plastic("intent", "rule", intent.intent_id, "Flowbite styles every delivery", table: Plastic::CLI::TABLE)

    result = call(intent.intent_id)

    assert_call result, code: 0, out: ["ruling: D1 Flowbite styles every delivery", "log:"]
  end

  def shown_times(intent_id) = call(intent_id).out.lines.grep(/\Alog: - /).map { |line| line.split[2] }

  def stored_times(intent_id) = store_graphs.retrieval.structure.work_log(intent_id).map(&:at)

  def test_the_log_lines_show_their_time_in_the_zone_of_the_machine_and_work_log_keeps_utc
    intent_id = open_intent.intent_id

    assert_equal [[], []], [shown_times(intent_id).grep(/Z\z/), stored_times(intent_id).grep_v(/Z\z/)]
  end

  def test_marks_a_superseded_ruling
    intent = open_intent
    plastic("intent", "rule", intent.intent_id, "Flowbite styles every delivery", table: Plastic::CLI::TABLE)
    plastic("intent", "rule", intent.intent_id, "Direct mode only", "--supersedes", "D1", table: Plastic::CLI::TABLE)

    result = call(intent.intent_id)

    assert_call result, code: 0, out: ["ruling: D1 Flowbite styles every delivery (superseded)", "ruling: D2 Direct mode only\n"]
  end
end
