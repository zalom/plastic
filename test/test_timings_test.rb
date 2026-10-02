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

  # Minitest.reporter is set only while plugins are initializing, before any
  # test runs (its own docs say so), so this drives the guard the same way
  # the real init does: no ENV var, no file, and no reporter ever touched.
  def test_without_a_timings_file_nothing_is_written
    ENV.delete("PLASTIC_TEST_TIMINGS")

    Minitest.plugin_test_timings_init({})

    refute_path_exists @path
  end

  # With PLASTIC_TEST_TIMINGS named, the real init path (a reporter already
  # set, as Minitest's plugin sequence guarantees) reads the ENV var once and
  # adds a TestTimings::Reporter at that path. A mutant that drops the
  # `path = ENV.fetch(...)` assignment reads an undefined local here instead
  # of failing this assertion, so this test catches it.
  def test_with_a_timings_file_a_reporter_is_added
    ENV["PLASTIC_TEST_TIMINGS"] = @path
    fake, added = fake_reporter
    original = Minitest.reporter
    Minitest.reporter = fake

    Minitest.plugin_test_timings_init({})

    assert_instance_of TestTimings::Reporter, added.call
  ensure
    Minitest.reporter = original
    ENV.delete("PLASTIC_TEST_TIMINGS")
  end

  def fake_reporter
    added = nil
    fake = Object.new
    fake.define_singleton_method(:<<) { |reporter| added = reporter }
    [fake, -> { added }]
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

  def check_caps(seconds, rerun:)
    File.write(@path, JSON.generate(seconds))
    out = StringIO.new
    caps = TestTimings::Caps.new(@path, rerun:, out:)
    caps.check
    [nil, out.string]
  rescue TestTimings::Caps::Failure => e
    [e, out.string]
  end

  def test_rerun_shells_to_bin_test_only_for_a_plain_file
    seen = nil
    runner = ->(*command, chdir:) { seen = [command, chdir] }

    TestTimings::Rerun.new(root: "/worktree", runner:).call("test/plain_test.rb")

    assert_equal [["bundle", "exec", "ruby", "bin/test", "--only", "test/plain_test.rb"], "/worktree"], seen
  end

  def test_rerun_shells_to_bin_test_system_for_a_varar_document
    seen = nil
    runner = ->(*command, chdir:) { seen = [command, chdir] }

    TestTimings::Rerun.new(root: "/worktree", runner:).call("varar/intent-new.md")

    assert_equal [%w[bundle exec ruby bin/test --system], "/worktree"], seen
  end
end
