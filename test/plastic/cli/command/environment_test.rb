# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandEnvironmentTest < Plastic::TestCase
  def session(env) = environment(env:).session

  def test_the_plastic_session_wins_over_the_harness_session
    assert_equal "p-1", session("PLASTIC_SESSION" => "p-1", "CLAUDE_CODE_SESSION_ID" => "c-1")
  end

  def test_a_blank_variable_falls_through_to_the_next
    assert_equal "x-1", session("PLASTIC_SESSION" => " ", "CODEX_THREAD_ID" => "x-1")
  end

  def test_no_session_variable_is_nil
    assert_nil session({})
  end
end
