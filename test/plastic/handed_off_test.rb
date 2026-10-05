# frozen_string_literal: true

require_relative "../test_helper"

class HandedOffTest < Plastic::TestCase
  def report(exit_code)
    out = StringIO.new
    printer = Plastic::CLI::TextOutput.new(out:, err: StringIO.new)
    code = Plastic::HandedOff.new(steps: %w[one two], next_command: "plastic again", because: "left", exit_code:).report(printer)
    printer.flush
    [code, out.string]
  end

  def test_report_numbers_the_steps_then_offers_the_next_call
    assert_equal [0, "1. one\n2. two\nnext: plastic again\nbecause: left\n"], report(0)
  end

  def test_report_returns_the_exit_code_the_outcome_set
    assert_equal 1, report(1).first
  end
end
