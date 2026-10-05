# frozen_string_literal: true

require_relative "../../test_helper"

class TextOutputTest < Plastic::TestCase
  def setup
    super
    @out = StringIO.new
  end

  def output = Plastic::CLI::TextOutput.new(out: @out, err: StringIO.new)

  def test_rows_line_up_on_the_widest_label
    output.row("intent", "7").row("wrote:", ["a", "b"]).next_step("plastic next", because: "why").flush

    assert_equal "intent  7\nwrote:  a\n        b\n\nnext: plastic next\nbecause: why\n", @out.string
  end

  def test_an_empty_row_prints_nothing_and_sets_no_width
    output.row("long label", []).row("id", "7").flush

    assert_equal "id  7\n", @out.string
  end

  def test_no_next_step_prints_only_the_rows
    output.flush

    assert_equal "", @out.string
  end

  def test_raw_text_prints_at_once
    output.raw("line")

    assert_equal "line\n", @out.string
  end

  def test_the_label_goes_on_the_first_line_of_a_value_only
    assert_equal ["ab  x", "    y"], Plastic::CLI::TextOutput.lines_for("ab", %w[x y], 4)
  end
end
