# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/archive"

class IntentArchiveUsageTest < Plastic::TestCase
  def call(*args) = plastic("intent", "archive", *args, table: Plastic::CLI::TABLE)

  def test_naming_neither_an_intent_nor_a_date_is_a_usage_error
    result = call

    assert_equal [2, true], [result.code, result.err.include?("give an intent ID or --older-than DATE")]
  end

  def test_naming_both_an_intent_and_a_date_is_a_usage_error
    result = call("1", "--older-than", "2026-02-01")

    assert_equal [2, true], [result.code, result.err.include?("exclude each other")]
  end

  def test_a_date_that_is_not_a_date_is_a_usage_error
    result = call("--older-than", "last week")

    assert_equal [2, true], [result.code, result.err.include?("cannot read")]
  end
end
