# frozen_string_literal: true

require_relative "support/kernel"

class EndValueTest < Minitest::Test
  def setup
    @out = StringIO.new
    @err = StringIO.new
    @output = Plastic::CLI::TextOutput.new(out: @out, err: @err)
  end

  def test_finished_prints_next_and_because_and_exits_0
    code = Plastic::Finished.new(next_command: "plastic next", because: "the chain ended").report(@output)
    @output.flush

    assert_equal 0, code
    assert_equal "next: plastic next\nbecause: the chain ended\n", @out.string
  end

  def test_handed_off_numbers_the_steps
    value = Plastic::HandedOff.new(steps: %w[one two], next_command: "plastic again", because: "left", exit_code: 1)
    code = value.report(@output)
    @output.flush

    assert_equal 1, code
    assert_equal "1. one\n2. two\nnext: plastic again\nbecause: left\n", @out.string
  end

  def test_failed_raises_a_failure_that_exits_1
    error = assert_raises(Plastic::CLI::Command::Failure) { Plastic::Failed.new(:code_a, "step", "broke").report(@output) }
    error.report(@output)

    assert_equal [1, 1], [Plastic::Failed.new(:code_a, "step", "broke").exit_code, error.exit_code]
    assert_equal "plastic: code_a, step: broke\n", @err.string
  end

  def test_refused_raises_a_refusal_that_exits_3
    error = assert_raises(Plastic::CLI::Command::Refusal) { Plastic::Refused.new(:code_a, "the owner holds it").report(@output) }
    error.report(@output)

    assert_equal [3, 3], [Plastic::Refused.new(:code_a, "x").exit_code, error.exit_code]
    assert_includes @err.string, "plastic: refused, the owner holds it\n"
  end
end
