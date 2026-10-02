# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_brief"
require_relative "../../../scripts/lib/plastic/commands/intent_rule"
require_relative "../../../scripts/lib/plastic/commands/node_add"

class IntentBriefTest < Plastic::TestCase
  def call(*args) = plastic("intent", "brief", *args, table: Plastic::CLI::TABLE)

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end

  def briefed_intent
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")
    plastic("intent", "rule", intent.intent_id, "Flowbite styles every delivery", table: Plastic::CLI::TABLE)
    plastic("intent", "rule", intent.intent_id, "Direct mode only", "--supersedes", "D1", table: Plastic::CLI::TABLE)
    plastic("node", "add", intent.intent_id, "do the thing", "--criterion", "it is done", table: Plastic::CLI::TABLE)
    intent
  end

  def test_names_the_goal_and_the_done_criteria
    intent = briefed_intent

    result = call(intent.intent_id)

    assert_equal 0, result.code
    assert_includes result.out, "goal: Alpha"
    assert_includes result.out, "criterion: ships"
  end

  def test_names_each_goal_line_the_spec_holds
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Goal\n\nClose the two blockers\nLock down guest orders\n\n## Done criteria\n- ships\n")

    result = call(intent.intent_id)

    assert_includes result.out, "goal: Close the two blockers\ngoal: Lock down guest orders\n"
    refute_includes result.out, "goal: Alpha"
  end

  def test_marks_the_superseded_ruling_and_keeps_the_other_plain
    intent = briefed_intent

    result = call(intent.intent_id)

    assert_includes result.out, "ruling: D1 Flowbite styles every delivery (superseded)"
    assert_includes result.out, "ruling: D2 Direct mode only"
    refute_includes result.out, "ruling: D2 Direct mode only (superseded)"
  end

  def test_names_the_ready_node_and_the_command_usage
    intent = briefed_intent

    result = call(intent.intent_id)

    assert_includes result.out, "ready: n1 do the thing"
    assert_includes result.out, "plastic node add ID"
    assert_includes result.out, "plastic edge add ID"
  end

  def test_misses_nothing_on_an_empty_intent
    intent = open_intent

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute_includes result.out, "ruling:"
    refute_includes result.out, "ready:"
  end
end
