# frozen_string_literal: true

require "json"
require_relative "../test_helper"

class FailedTest < Plastic::TestCase
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

  def test_a_stop_a_workflow_designed_tells_its_message_with_no_workflow_key
    out = StringIO.new
    error = Plastic::Failed.new("see the findings above", source: "code_a, gate")
    error.tell(Plastic::CLI::JsonOutput.new(out:, err: StringIO.new), Plastic::CLI::Offer.none("x"))

    assert_equal "see the findings above", JSON.parse(out.string).dig("result", "error", "message")
  end

  def test_a_step_that_raised_tells_the_workflow_key
    out = StringIO.new
    error = Plastic::Failed.raised(:code_a, "step", ArgumentError.new("bad"))
    error.tell(Plastic::CLI::JsonOutput.new(out:, err: StringIO.new), Plastic::CLI::Offer.none("x"))

    assert_equal "code_a, step: ArgumentError: bad", JSON.parse(out.string).dig("result", "error", "message")
  end

  def test_a_failed_call_prints_no_stderr_line_with_a_workflow_key
    result = plastic("graph", "check", "9", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    refute_match(/code_\w+,/, result.err)
  end
end
