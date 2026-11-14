# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "stringio"
require "tmpdir"
require_relative "../bin/lib/test_timings"

# The gate's timing extension and cap check. Every test
# drives the two public classes, Reporter and Caps, the same way the gate's
# step and the plugin hook do.
class TestTimingsTest < Minitest::Test
  FakeResult = Struct.new(:klass, :name, :time)

  class SampleTest < Minitest::Test
    def self.marker_file = __FILE__

    def test_one = nil

    def test_two = nil
  end

  def setup
    @dir = Dir.mktmpdir("test-timings")
    @path = File.join(@dir, "timings.json")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_each_file_gets_the_sum_of_its_tests
    reporter = TestTimings::Reporter.new(@path)
    reporter.record(FakeResult.new("TestTimingsTest::SampleTest", "test_one", 1.5))
    reporter.record(FakeResult.new("TestTimingsTest::SampleTest", "test_two", 2.5))
    reporter.report

    totals = JSON.parse(File.read(@path))
    file = SampleTest.marker_file.delete_prefix("#{File.expand_path("..", __dir__)}/")

    assert_in_delta 4.0, totals.fetch(file), 0.0001
  end

  # A composite reporter that keeps what is added to it.
  class Composite
    attr_reader :added

    def initialize = @added = []

    def <<(reporter) = @added << reporter
  end

  def test_without_a_timings_file_no_reporter_is_added
    composite = Composite.new

    Minitest.plugin_test_timings_init({}, env: {}, composite:)

    assert_empty composite.added
  end

  def test_with_a_timings_file_a_reporter_is_added
    composite = Composite.new

    Minitest.plugin_test_timings_init({}, env: { "PLASTIC_TEST_TIMINGS" => @path }, composite:)

    assert_equal [TestTimings::Reporter], composite.added.map(&:class)
  end

  def test_a_varar_class_is_booked_to_its_document_from_the_list
    reporter = TestTimings::Reporter.new(@path)
    reporter.record(FakeResult.new("Var_varar_intent_new_md", "test_example", 3.0))
    reporter.report

    totals = JSON.parse(File.read(@path))

    assert_in_delta 3.0, totals.fetch("varar/intent-new.md"), 0.0001
  end

  def test_the_caps_are_5_seconds_per_file_and_10_per_document
    never_called = ->(_file) { raise "rerun must not run" }
    _, out_one = check_caps({ "test/plain_test.rb" => 4.9, "varar/intent-new.md" => 9.9 }, rerun: never_called)
    _, out_two = check_caps({ "varar/intent-new.md" => 5.5 }, rerun: never_called)

    assert_empty out_one
    assert_empty out_two
  end

  def test_a_file_under_its_cap_on_rerun_passes
    error, out = check_caps({ "test/plain_test.rb" => 5.5 }, rerun: ->(_file) { 4.0 })

    assert_nil error
    assert_includes out, "5.5"
    assert_includes out, "4.0"
  end

  def test_a_file_over_its_cap_on_rerun_fails
    error, out = check_caps({ "test/plain_test.rb" => 5.5 }, rerun: ->(_file) { 6.0 })

    refute_nil error
    assert_includes out, "5.5"
    assert_includes out, "6.0"
  end

  def test_a_file_over_its_cap_is_named_with_its_time
    error, out = check_caps({ "test/plain_test.rb" => 5.5 }, rerun: ->(_file) { 6.2 })

    assert_includes error.message, "test/plain_test.rb"
    assert_includes error.message, "6.2"
    assert_includes out, "test/plain_test.rb"
  end

  def test_a_missing_timings_file_fails_and_names_the_path
    error = assert_raises(TestTimings::Caps::Failure) { TestTimings::Caps.new(@path, rerun: nil).check }

    assert_equal "missing timings file: #{@path}", error.message
  end



  def test_a_timings_file_cut_off_in_the_middle_did_not_run
    File.write(@path, %({"test/a_test.rb": 0.2, "test/b_te))

    error = assert_raises(TestTimings::Caps::NotRun) { TestTimings::Caps.new(@path, rerun: nil).check }

    assert_includes error.message, @path
  end

  def test_without_a_varar_config_a_result_is_booked_to_its_source_file
    documents = TestTimings::Documents.new(root: File.dirname(SampleTest.marker_file))

    assert_equal "test_timings_test.rb", documents.book(FakeResult.new("TestTimingsTest::SampleTest", "test_one", 1.0))
  end

  def check_caps(seconds, rerun:)
    File.write(@path, JSON.generate(seconds))
    out = StringIO.new
    caps = TestTimings::Caps.new(@path, rerun:, out:)
    caps.check
    [nil, out.string]
  rescue TestTimings::Caps::Failure => e
    [e, out.string]
  end
end

class TestTimingsVerdictTest < Minitest::Test
  def verdict(seconds, rerun)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "timings.json")
      File.write(path, JSON.generate(seconds))
      err = StringIO.new
      [TestTimings.verdict(path, rerun:, err:), err.string]
    end
  end

  def test_a_file_under_its_cap_exits_0_in_silence
    assert_equal [0, ""], verdict({ "test/plain_test.rb" => 1.0 }, ->(_file) { 1.0 })
  end

  def test_a_file_over_its_cap_exits_1_and_names_it
    status, message = verdict({ "test/plain_test.rb" => 5.5 }, ->(_file) { 6.2 })

    assert_equal 1, status
    assert_includes message, "test/plain_test.rb"
  end

  def test_a_rerun_that_could_not_run_exits_3_and_says_why
    rerun = ->(_file) { raise TestTimings::Caps::NotRun, "test/plain_test.rb rerun failed: load failed" }

    assert_equal [3, "test/plain_test.rb rerun failed: load failed\n"], verdict({ "test/plain_test.rb" => 5.5 }, rerun)
  end
end

class TestTimingsCliTest < Minitest::Test
  def test_a_call_without_a_path_prints_the_usage_and_exits_2
    err = StringIO.new

    assert_equal 2, TestTimings.cli(["check"], err:)
    assert_equal "Usage: bin/lib/test_timings.rb check PATH\n", err.string
  end

  def test_the_file_run_as_the_program_exits_with_the_command_line_status
    exited = assert_raises(SystemExit) { TestTimings.main([], program: "a", file: "a", err: StringIO.new) }

    assert_equal 2, exited.status
  end

  def test_the_file_loaded_by_another_program_exits_nothing
    assert_nil TestTimings.main([], program: "a", file: "b")
  end

  def test_a_check_call_gives_the_verdict_of_the_named_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "timings.json")
      File.write(path, JSON.generate({ "test/plain_test.rb" => 1.0 }))

      assert_equal 0, TestTimings.cli(["check", path], rerun: ->(_file) { 1.0 }, err: StringIO.new)
    end
  end
end

class TestTimingsRerunTest < Minitest::Test
  def test_rerun_shells_to_bin_test_only_for_a_plain_file
    seen = nil
    runner = lambda { |*command, chdir:|
      seen = [command, chdir]
      ["", success]
    }

    TestTimings::Rerun.new(root: "/worktree", runner:).call("test/plain_test.rb")

    assert_equal [["bundle", "exec", "ruby", "bin/test", "--only", "test/plain_test.rb"], "/worktree"], seen
  end

  def test_rerun_selects_only_the_named_varar_document
    seen = nil
    runner = lambda { |*command, chdir:|
      seen = [command, chdir]
      ["", success]
    }

    TestTimings::Rerun.new(root: "/worktree", runner:).call("varar/intent-new.md")

    assert_equal [["bundle", "exec", "ruby", "bin/test", "--name", "/\\AVar_varar_intent_new_md#/", "--system"], "/worktree"], seen
  end

  def test_a_failed_rerun_never_passes_the_cap
    runner = ->(*, **) { ["load failed", Struct.new(:success?).new(false)] }

    error = assert_raises(TestTimings::Caps::Failure) do
      TestTimings::Rerun.new(runner:).call("test/missing_test.rb")
    end

    assert_includes error.message, "load failed"
  end

  def success = Struct.new(:success?).new(true)
end
