# frozen_string_literal: true

require_relative "../test_helper"

class EndValueTest < Plastic::TestCase
  def setup
    super
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
end
