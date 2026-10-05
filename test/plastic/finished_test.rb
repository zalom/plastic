# frozen_string_literal: true

require_relative "../test_helper"

class FinishedTest < Plastic::TestCase
  def test_closing_takes_the_offer_and_the_because_of_the_outcome
    assert_equal Plastic::Finished.new(next_command: "plastic kernel two ada", because: "greeted ada"),
      Plastic::Finished.closing(Flows::Greet, :done, context)
  end

  def test_a_closing_line_with_a_hole_fails_the_call
    failed = Plastic::Finished.closing(Flows::Hole, :done, context(declared: %i[missing], facts: {}))

    assert_equal [:code_hole, "closing"], [failed.workflow, failed.step]
  end

  def test_report_offers_the_next_command_and_exits_zero
    out = StringIO.new
    printer = Plastic::CLI::TextOutput.new(out:, err: StringIO.new)

    code = Plastic::Finished.new(next_command: "plastic next", because: "done").report(printer)
    printer.flush

    assert_equal [0, "next: plastic next\nbecause: done\n"], [code, out.string]
  end
end
