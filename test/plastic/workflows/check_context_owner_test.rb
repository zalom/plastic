# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/check_context_owner"

class CheckContextOwnerTest < Plastic::TestCase
  def check(intent_id, from: nil) = run_workflow(Plastic::Workflows::CheckContextOwner, intent_id:, from:).first

  def test_a_known_intent_with_a_submission_goes_to_submit
    open_intent

    assert_equal :submit, check("1", from: "context.md")
  end

  def test_a_known_intent_with_no_submission_goes_to_read
    open_intent

    assert_equal :read, check("1")
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "code_check_context_owner, gate: no intent 9 in owning store", check("9").message
  end

  def test_a_malformed_id_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { check("../1") }

    assert_equal "invalid intent id \"../1\"", error.message
  end
end
