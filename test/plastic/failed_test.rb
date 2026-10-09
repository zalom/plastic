# frozen_string_literal: true

require "json"
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

  def test_report_raises_the_failure_with_the_bare_reason_and_the_workflow_key
    error = assert_raises(Plastic::CLI::Command::Failure) { Plastic::Failed.new(:code_a, "step", "broke").report(nil) }

    assert_equal ["broke", "code_a, step"], [error.message, error.source]
  end

  def test_the_text_error_line_drops_the_workflow_key
    err = StringIO.new
    Plastic::CLI::TextOutput.new(out: StringIO.new, err: err).failed("broke", Plastic::CLI::Offer.none("broke"), source: "code_a, step")

    assert_equal "plastic: broke\n", err.string
  end

  def test_the_json_error_keeps_the_workflow_key
    out = StringIO.new
    Plastic::CLI::JsonOutput.new(out:, err: StringIO.new).failed("broke", Plastic::CLI::Offer.none("broke"), source: "code_a, step")

    assert_equal "code_a, step: broke", JSON.parse(out.string).dig("result", "error", "message")
  end

  def test_a_failed_call_prints_no_stderr_line_with_a_workflow_key
    result = plastic("graph", "check", "9", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    refute_match(/code_\w+,/, result.err)
  end
end
