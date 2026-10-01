# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

class OutputTest < Plastic::TestCase
  def setup
    super
    @out = StringIO.new
    @err = StringIO.new
  end

  def output(json: false) = (json ? Plastic::CLI::JsonOutput : Plastic::CLI::TextOutput).new(out: @out, err: @err)

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

  def test_a_project_with_no_next_step_prints_a_null_next_in_json
    printer = output(json: true).row("id", "7")
    printer.flush("b")

    assert_equal({ "result" => { "id" => "7" }, "next" => nil, "because" => nil }, JSON.parse(@out.string))
  end

  def test_flush_prints_once
    printer = output.next_step("plastic next", because: "why")
    printer.flush
    printer.flush

    assert_equal "next: plastic next\nbecause: why\n", @out.string
  end

  def test_a_scoped_command_keeps_the_project
    printer = output.next_step("plastic intent show 7", because: "why")
    printer.flush("my app")

    assert_includes @out.string, "next: plastic intent show 7 --project my\\ app\n"
  end

  def test_a_command_that_names_its_project_is_left_alone
    printer = output.next_step("plastic intent show 7 --project a", because: "why")
    printer.flush("b")

    assert_includes @out.string, "next: plastic intent show 7 --project a\n"
  end

  def test_an_unscoped_command_gets_no_project
    printer = output.next_step("plastic status", because: "why")
    printer.flush("b")

    assert_includes @out.string, "next: plastic status\n"
  end

  def test_raw_text_prints_at_once
    output.raw("line")

    assert_equal "line\n", @out.string
  end

  def test_json_keeps_raw_lines_under_output
    output(json: true).raw("line").row("id", "7").next_step("plastic next", because: "why").flush

    assert_equal({ "result" => { "id" => "7", "output" => ["line"] }, "next" => "plastic next", "because" => "why" },
      JSON.parse(@out.string))
  end

  def test_json_is_known
    assert_predicate output(json: true), :json?
    refute_predicate output, :json?
  end

  def test_a_document_prints_whole_and_ends_the_output
    printer = output.document({ "a" => 1 })
    printer.flush

    assert_equal({ "a" => 1 }, JSON.parse(@out.string))
  end

  def test_usage_prints_the_message_and_the_banner
    output.usage("missing ID", "plastic intent show ID")

    assert_equal "plastic: missing ID\nplastic intent show ID\n", @err.string
  end

  def test_refused_names_the_owner
    output.refused("the owner holds it")

    assert_equal "plastic: refused, the owner holds it\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n",
      @err.string
  end

  def test_failed_prints_the_message
    output.failed("it broke")

    assert_equal "plastic: it broke\n", @err.string
  end

  def test_an_error_in_json_prints_the_error_document
    output(json: true).failed("it broke")

    assert_equal({ "result" => { "error" => { "kind" => "failed", "message" => "it broke" } }, "next" => "none", "because" => "it broke" },
      JSON.parse(@out.string))
  end

  def test_usage_in_json_is_kind_usage
    output(json: true).usage("missing ID", "banner")

    assert_equal "usage", JSON.parse(@out.string).dig("result", "error", "kind")
  end

  def test_refused_in_json_is_kind_refused
    output(json: true).refused("owner")

    assert_equal "refused", JSON.parse(@out.string).dig("result", "error", "kind")
  end
end
