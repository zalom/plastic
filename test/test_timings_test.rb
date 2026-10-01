# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require_relative "../bin/lib/test_timings"

# Intent 397, D5: the gate's timing extension and cap check. Every test
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

  def test_a_varar_class_is_booked_to_its_document_from_the_list
    reporter = TestTimings::Reporter.new(@path)
    reporter.record(FakeResult.new("Var_varar_store_layout_md", "test_example", 3.0))
    reporter.report

    totals = JSON.parse(File.read(@path))

    assert_in_delta 3.0, totals.fetch("varar/store-layout.md"), 0.0001
  end

  def test_the_caps_are_5_seconds_per_file_and_10_per_document
    File.write(@path, JSON.generate({ "test/plain_test.rb" => 4.9, "varar/store-layout.md" => 9.9 }))
    never_called = ->(_file) { raise "rerun must not run" }

    TestTimings::Caps.new(@path, rerun: never_called).check!

    File.write(@path, JSON.generate({ "varar/store-layout.md" => 5.5 }))

    TestTimings::Caps.new(@path, rerun: never_called).check!
  end

  def test_a_file_over_its_cap_fails_only_when_its_rerun_is_over_too
    File.write(@path, JSON.generate({ "test/plain_test.rb" => 5.5 }))
    under_on_rerun = TestTimings::Caps.new(@path, rerun: ->(_file) { 4.0 })

    under_on_rerun.check!

    File.write(@path, JSON.generate({ "test/plain_test.rb" => 5.5 }))
    over_on_rerun = TestTimings::Caps.new(@path, rerun: ->(_file) { 6.0 })

    assert_raises(TestTimings::Caps::Failure) { over_on_rerun.check! }
  end

  def test_a_file_over_its_cap_is_named_with_its_time
    File.write(@path, JSON.generate({ "test/plain_test.rb" => 5.5 }))
    caps = TestTimings::Caps.new(@path, rerun: ->(_file) { 6.2 })

    error = assert_raises(TestTimings::Caps::Failure) { caps.check! }

    assert_includes error.message, "test/plain_test.rb"
    assert_includes error.message, "6.2"
  end
end
