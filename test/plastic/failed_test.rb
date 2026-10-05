# frozen_string_literal: true

require_relative "../test_helper"

class FailedTest < Plastic::TestCase
  def test_the_message_names_the_workflow_the_step_and_the_reason
    assert_equal "code_a, step: broke", Plastic::Failed.new(:code_a, "step", "broke").message
  end

  def test_a_raised_error_names_its_class_in_the_reason
    failed = Plastic::Failed.raised(:code_a, "step", ArgumentError.new("bad"))

    assert_equal "ArgumentError: bad", failed.reason
  end

  def test_a_failure_exits_one
    assert_equal 1, Plastic::Failed.new(:code_a, "step", "broke").exit_code
  end

  def test_report_raises_the_failure_the_boundary_prints
    error = assert_raises(Plastic::CLI::Command::Failure) { Plastic::Failed.new(:code_a, "step", "broke").report(nil) }

    assert_equal "code_a, step: broke", error.message
  end
end
