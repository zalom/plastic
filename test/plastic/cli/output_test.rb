# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

class OutputTest < Plastic::TestCase
  def setup
    super
    @out = StringIO.new
    @err = StringIO.new
  end

  def output = Plastic::CLI::TextOutput.new(out: @out, err: @err)

  def test_flush_prints_the_output_only_once
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

  def test_json_is_off_for_text
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
end
