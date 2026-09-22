# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/cli/legacy"
require_relative "../../scripts/lib/cli/output"
require "stringio"
require "json"

class CliJsonCaptureTest < Minitest::Test
  def setup
    @out = StringIO.new
    @err = StringIO.new
    @output = Plastic::CLI::Output.new(out: @out, err: @err, json: true)
  end

  def payload
    JSON.parse(@out.string)
  end

  def adapter(text, status)
    runner = ->(_path, _args, capture:) {
      raise "stdout must be captured" unless capture
      [text, status]
    }
    Plastic::CLI::Legacy.new(env: {}, runner: runner, output: @output, json: true)
  end

  def test_child_prose_is_retained_inside_one_json_envelope
    status = adapter("Child prose\n", 0).run("example")
    @output.flush(json: true)

    assert_equal 0, status
    assert_equal ["Child prose\n"], payload.dig("result", "output")
  end

  def test_empty_child_stdout_adds_no_payload
    adapter("", 0).run("example")
    @output.flush(json: true)

    assert_equal({}, payload.fetch("result"))
  end

  def test_child_failure_keeps_output_and_failure_details
    status = adapter("Failure detail", 7).run("example")
    @output.failed("example exited #{status}")

    assert_equal 7, status
    assert_equal ["Failure detail"], payload.dig("result", "output")
    assert_equal "failed", payload.dig("result", "error", "kind")
  end

  def test_usage_errors_emit_json_and_stderr
    @output.usage("missing id", "plastic intent show ID")

    assert_equal "usage", payload.dig("result", "error", "kind")
    assert_includes @err.string, "plastic intent show ID"
  end

  def test_document_is_written_once
    @output.document("status" => "pass")
    @output.flush(json: true)

    assert_equal({"status" => "pass"}, payload)
  end

  def test_existing_project_flag_is_preserved
    @output.project = "other"
    @output.next_step("plastic intent show 1 --project chosen", because: "scope")
    @output.flush(json: true)

    assert_equal "plastic intent show 1 --project chosen", payload.fetch("next")
  end

  def test_no_next_action_is_preserved
    @output.project = "sample"
    @output.flush(json: true)

    assert_nil payload.fetch("next")
  end
end
