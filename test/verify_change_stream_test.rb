# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "rbconfig"
require "stringio"
require "tmpdir"

load File.expand_path("../bin/verify-change", __dir__) unless defined?(VerifyChange)

# The gate's own runner starts each step as a child, copies what it prints to the gate's output,
# and keeps that text so a missed target can be told from a tool that did not run.
class VerifyChangeStreamTest < Minitest::Test
  MISS = "Score (80.0) is below the minimum 90.0"

  def setup
    @root = Dir.mktmpdir("verify-change-stream")
    @out = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def stream(script)
    VerifyChange.new([], root: @root, out: @out, err: StringIO.new).stream({},[RbConfig.ruby, "-e", script])
  end

  def test_the_runner_answers_the_exit_code_with_the_text_the_step_printed
    code, text = stream("puts #{MISS.dump}; exit 1")

    assert_equal [1, "#{MISS}\n"], [code, text]
  end

  def test_the_runner_copies_what_the_step_printed_to_the_gate_output
    stream("puts #{MISS.dump}; exit 1")

    assert_includes @out.string, MISS
  end
end
