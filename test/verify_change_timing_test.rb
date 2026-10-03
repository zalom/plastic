# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"

load File.expand_path("../bin/verify-change", __dir__) unless defined?(VerifyChange)

# The gate wires the timing extension and cap check into its
# own steps, through the same `step` method every other check uses, so the
# sandbox HOME and PLASTIC_TMP apply to them too.
class VerifyChangeTimingTest < Minitest::Test
  TEST_FILE = "test/plastic/new_routine_test.rb"
  SOURCE_FILE = "bin/lib/new_routine.rb"

  def setup
    @root = Dir.mktmpdir("verify-change-timing")
    write(TEST_FILE, "")
    write(SOURCE_FILE, "")
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write(path, body)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  def plan(changed:, rails: false, suite: VerifyChange::MINITEST, **options)
    VerifyChange.new([], root: @root, err: @err, sandbox: { "HOME" => "/nowhere", "PLASTIC_TMP" => "/nowhere" }, **options)
      .plan(changed:, extra_tests: [], base: "HEAD", rails:, suite:)
  end

  def test_the_tests_step_records_timings
    step = plan(changed: [TEST_FILE]).steps.find { |candidate| candidate.title == "Tests with coverage" }

    assert_equal "/nowhere/test_timings.json", step.env.fetch("PLASTIC_TEST_TIMINGS")
    assert_includes step.command, File.join(@root, "bin/lib/test_timings")
  end

  def test_coverage_starts_before_the_timing_extension_loads
    write("test/test_helper.rb", "require 'coverage'; Coverage.start\n")
    write("bin/lib/test_timings.rb", "abort 'coverage started too late' unless Coverage.running?\n")
    step = plan(changed: [TEST_FILE]).steps.find { |candidate| candidate.title == "Tests with coverage" }

    output, status = Open3.capture2e(*step.command.drop(2), chdir: @root)

    assert_predicate status, :success?, output
  end

  def test_the_timing_check_is_its_own_step_after_the_tests
    titles = plan(changed: [TEST_FILE]).steps.map(&:title)

    tests_index = titles.index("Tests with coverage")
    timing_index = titles.index("Timing check")

    refute_nil timing_index
    assert_operator timing_index, :>, tests_index
  end

  def test_missing_timings_fail_the_step
    step = plan(changed: [TEST_FILE]).steps.find { |candidate| candidate.title == "Timing check" }
    missing = File.join(Dir.mktmpdir("verify-change-timing-missing"), "absent.json")

    _, status = Open3.capture2e(step.env, *step.command.map { |word| (word == "/nowhere/test_timings.json") ? missing : word }, chdir: @root)

    refute_predicate status, :success?
  end

  def test_other_suites_skip_the_timing_check_and_say_so
    spec_file = "spec/new_routine_spec.rb"
    write(spec_file, "")

    titles = plan(changed: [spec_file], suite: VerifyChange::RSPEC).steps.map(&:title)

    refute_includes titles, "Timing check"
    assert_includes @err.string, "Timing check skipped"
  end

  def test_rails_skips_the_timing_check_and_says_so
    titles = plan(changed: [TEST_FILE], rails: true).steps.map(&:title)

    refute_includes titles, "Timing check"
    assert_includes @err.string, "Timing check skipped"
  end

  def test_the_mutation_step_writes_json_under_the_sandbox
    step = plan(changed: [SOURCE_FILE, TEST_FILE], mutation: true).steps.find { |candidate| candidate.title == "Mutation testing" }

    output_index = step.command.index("--output")

    refute_nil output_index
    assert_equal "/nowhere/mutation_report.json", step.command[output_index + 1]
  end

  def test_the_frozen_mutation_step_is_left_out_of_the_plan
    titles = plan(changed: [SOURCE_FILE, TEST_FILE]).steps.map(&:title)

    refute_includes titles, "Mutation testing"
  end
end
