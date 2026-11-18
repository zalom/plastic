# frozen_string_literal: true

require_relative "../../test_helper"

class ContextPrintedTest < Plastic::TestCase
  Output = Struct.new(:calls) do
    def raw(line) = calls << [:raw, line]

    def row(label, value) = calls << [:row, label, value]
  end

  def test_lines_gives_the_text_of_the_lines_only
    printed = Plastic::Context::Printed.new
    printed.line("one")
    printed.row("results", [1])

    assert_equal ["one"], printed.lines
  end

  def test_print_to_replays_the_entries_in_order
    printed = Plastic::Context::Printed.new
    printed.line("one")
    printed.row("results", [1])
    output = Output.new([])
    printed.print_to(output)

    assert_equal [[:raw, "one"], [:row, "results", [1]]], output.calls
  end
end
