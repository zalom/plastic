# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_show"
require_relative "../../../scripts/lib/plastic/commands/intent_rule"

class IntentShowTest < Plastic::TestCase
  def call(*args) = plastic("intent", "show", *args, table: Plastic::CLI::TABLE)

  def test_unknown_id_exits_1
    result = call("9")

    assert_equal 1, result.code
  end

  def test_shows_the_intent_and_its_criteria_count
    intent = open_intent

    result = call(intent.intent_id)

    assert_equal 0, result.code
    assert_includes result.out, "intent: #{intent.intent_id} Alpha (open)"
    assert_includes result.out, "criteria: 0"
  end

  def test_shows_a_ruling_and_the_last_savepoint
    intent = open_intent
    plastic("intent", "rule", intent.intent_id, "Flowbite styles every delivery", table: Plastic::CLI::TABLE)

    result = call(intent.intent_id)

    assert_includes result.out, "ruling: D1 Flowbite styles every delivery"
    assert_includes result.out, "savepoint:"
  end
end
