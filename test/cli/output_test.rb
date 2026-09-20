# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"
require_relative "../../scripts/lib/cli/output"

class CliOutputTest < Minitest::Test
  def setup
    @out = StringIO.new
    @err = StringIO.new
    @output = Plastic::CLI::Output.new(out: @out, err: @err)
  end

  def test_one_row_prints_the_label_and_the_value
    @output.row("project", "plastic")
    @output.flush

    assert_equal "project  plastic\n", @out.string
  end

  def test_the_label_column_is_as_wide_as_the_longest_label
    @output.row("id", "363")
    @output.row("frontier", "Batch 1")
    @output.flush

    assert_equal "id        363\nfrontier  Batch 1\n", @out.string
  end

  def test_a_list_value_prints_one_line_each_under_a_single_label
    @output.row("active", ["363  the command line", "367  the databases"])
    @output.flush

    assert_equal "active  363  the command line\n        367  the databases\n", @out.string
  end

  def test_an_empty_list_prints_nothing_for_that_row
    @output.row("active", [])
    @output.row("store", "global")
    @output.flush

    assert_equal "store  global\n", @out.string
  end

  def test_the_next_step_follows_the_rows_after_a_blank_line
    @output.row("project", "plastic")
    @output.next_step("plastic status", because: "it names the work")
    @output.flush

    assert_equal "project  plastic\n\nnext: plastic status\nbecause: it names the work\n", @out.string
  end

  def test_a_next_step_alone_prints_without_a_leading_blank_line
    @output.next_step("plastic help", because: "nothing is installed yet")
    @output.flush

    assert_equal "next: plastic help\nbecause: nothing is installed yet\n", @out.string
  end

  def test_json_carries_the_rows_the_next_step_and_the_reason
    @output.row("project", "plastic")
    @output.row("active", %w[363 367])
    @output.next_step("plastic status", because: "it names the work")
    @output.flush(json: true)

    assert_equal({"result" => {"project" => "plastic", "active" => %w[363 367]},
                   "next" => "plastic status", "because" => "it names the work"},
      JSON.parse(@out.string))
  end

  def test_json_without_a_next_step_carries_null
    @output.row("project", "plastic")
    @output.flush(json: true)

    assert_equal({"result" => {"project" => "plastic"}, "next" => nil, "because" => nil},
      JSON.parse(@out.string))
  end

  def test_json_ends_with_one_newline
    @output.row("project", "plastic")
    @output.flush(json: true)

    assert @out.string.end_with?("}\n"), "the JSON result must end with one newline"
  end

  def test_nothing_reaches_the_error_stream_on_a_result
    @output.row("project", "plastic")
    @output.next_step("plastic status", because: "it names the work")
    @output.flush

    assert_empty @err.string
  end

  def test_usage_goes_to_the_error_stream_with_the_banner
    @output.usage("invalid option: --nope", "plastic status [--json]")

    assert_equal "plastic: invalid option: --nope\nplastic status [--json]\n", @err.string
    assert_empty @out.string
  end

  def test_a_refusal_goes_to_the_error_stream_and_names_the_owner
    @output.refused("a live session holds the lock on 363")

    assert_equal "plastic: refused, a live session holds the lock on 363\n" \
                 "This step belongs to the owner. Stop and ask; do not retry with a flag.\n",
      @err.string
  end

  def test_a_failure_goes_to_the_error_stream
    @output.failed("install.rb exited 7")

    assert_equal "plastic: install.rb exited 7\n", @err.string
  end

  def test_flushing_twice_prints_once
    @output.row("project", "plastic")
    @output.flush
    @output.flush

    assert_equal "project  plastic\n", @out.string
  end
end
