# frozen_string_literal: true

require_relative "../test_helper"

class RoutineFailureTest < Plastic::TestCase
  def test_a_refusal_gate_exits_3_with_the_owner_line
    call = plastic("kernel", "gate", "hold")

    assert_equal 3, call.code
    assert_equal "plastic: refused, the owner holds hold\n" \
                 "This step belongs to the owner. Stop and ask; do not retry with a flag.\n", call.err
    assert_equal "refused", routine_run("kernel gate", nil).status
  end

  def test_a_failure_gate_exits_1_and_names_the_workflow
    call = plastic("kernel", "gate", "break")

    assert_equal 1, call.code
    assert_equal "plastic: code_hold, gate: the check broke on break\n", call.err
    assert_equal 1, routine_run("kernel gate", nil).exit_code
  end

  def test_a_passing_gate_lets_the_chain_finish
    call = plastic("kernel", "gate", "pass")

    assert_equal 0, call.code
    assert_equal "next: none\nbecause: passed pass\n", call.out
  end

  def test_a_step_that_raises_fails_with_the_error
    call = plastic("kernel", "break")

    assert_equal 1, call.code
    assert_equal "plastic: code_break, explode: RuntimeError: boom\n", call.err
  end

  def test_a_step_whose_done_check_still_fails_fails_the_call
    call = plastic("kernel", "stuck")

    assert_equal 1, call.code
    assert_equal "plastic: code_stuck, never lands: the step ran and its done check still fails\n", call.err
  end

  def test_a_closing_line_with_no_value_fails_the_call
    call = plastic("kernel", "hole")

    assert_equal 1, call.code
    assert_includes call.err, "code_hole, closing: Plastic::Invalid: no value for missing"
  end

  def test_a_hand_off_that_stops_as_a_failure_exits_1
    call = plastic("kernel", "review")

    assert_equal 1, call.code
    assert_equal "1. Review the change\nnext: none\nbecause: the review is open\n", call.out
  end

  def test_a_database_error_fails_the_call
    FileUtils.rm_rf(@plastic_home)
    File.write(@plastic_home, "not a directory")
    call = plastic("kernel", "gate", "pass")

    assert_equal 1, call.code
    assert_includes call.err, "home.db"
  end
end
