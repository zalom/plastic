# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "lib/bin_test_support"

# Drives bin/test as a subprocess against a
# tmpdir root holding tiny fixture test files, never the real suite: the real
# bin/test and failures_reporter.rb are copied into the fixture root so the
# script's own __dir__-relative paths resolve inside the tmpdir.
class BinTestTest < Minitest::Test
  include BinTestSupport

  POISON = <<~RUBY
    raise "b_test.rb must never load under --only a_test.rb"
  RUBY

  def test_only_loads_named_files
    write_test("a_test", GREEN)
    write_test("b_test", POISON)
    out, err, status = run_bin_test("--only", "test/a_test.rb")

    assert_predicate status, :success?, "expected success, got: #{out}#{err}"
    assert_includes out, "1 runs, 1 assertions, 0 failures, 0 errors"
  end

  def test_only_missing_file_exit_2
    write_test("a_test", GREEN)
    _out, err, status = run_bin_test("--only", "test/no_such_test.rb")

    assert_equal 2, status.exitstatus
    assert_includes err, "no_such_test.rb"
  end

  def test_green_run_prints_summary_only
    write_test("a_test", GREEN)
    out, _err, status = run_bin_test("--only", "test/a_test.rb")

    assert_predicate status, :success?
    lines = out.each_line.map(&:chomp).reject(&:empty?)

    assert_equal 1, lines.length, "expected exactly one line, got: #{out.inspect}"
    assert_match(/\A\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips\z/, lines.first)
  end

  def test_red_run_prints_failures_and_summary
    write_test("a_test", RED)
    out, _err, status = run_bin_test("--only", "test/a_test.rb")

    refute_predicate status, :success?
    assert_equal 3, ["a_test.rb", "expected failure message", "1 runs, 1 assertions, 1 failures, 0 errors"].count { |text| out.include?(text) }
  end

  def test_full_run_summary_parses_as_before
    write_test("a_test", GREEN)
    out, _err, status = run_bin_test

    assert_predicate status, :success?
    lines = out.each_line.map(&:chomp).reject(&:empty?)

    assert_equal 1, lines.length, "expected exactly one line, got: #{out.inspect}"
    assert_match(/\A\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips\z/, lines.first)
  end

  def test_end_to_end_layer_selects_the_varar_runner
    write_test("a_test", GREEN)
    write_test("varar_test", GREEN)
    out, _err, status = run_bin_test("--end-to-end", "--list")

    assert_predicate status, :success?
    assert_equal "test/varar_test.rb", out.strip
  end

  def test_system_flag_is_refused_as_unknown
    write_test("a_test", GREEN)
    _out, err, status = run_bin_test("--system", "--list")

    assert_equal 2, status.exitstatus
    assert_includes err, "unknown option: --system"
  end

  def test_no_workflow_names_the_system_flag
    workflows = Dir.glob(File.join(REPO, ".github", "workflows", "*.yml"))

    refute_empty workflows
    workflows.each { |path| refute_includes File.read(path), "--system", path }
  end

  def test_list_still_prints_files
    write_test("a_test", GREEN)
    out, _err, status = run_bin_test("--list")

    assert_predicate status, :success?
    assert_includes out, "test/a_test.rb"
  end
end
