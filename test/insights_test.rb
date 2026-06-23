# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../scripts/lib/insights"

# Library-level tests for the insight write path (intent 82). Hermetic:
# Dir.mktmpdir isolation, injected Time.utc(...) for determinism, single
# process (loaded by bin/test). No eval, no ENV / global seam.
class InsightsTest < Minitest::Test
  # A fixed injected time rendering 2026-06-24T08:13:05Z.
  T = Time.utc(2026, 6, 24, 8, 13, 5)

  def setup
    @root = Dir.mktmpdir("insights")
    @dir = File.join(@root, "82--demo")
    FileUtils.mkdir_p(@dir)
    @intent_file = File.join(@dir, "82--demo.md")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write_intent(body)
    File.write(@intent_file, body)
  end

  def read_intent
    File.read(@intent_file)
  end

  # Lines under the `## Insights` heading, in order, up to the next `## ` or EOF.
  def insight_lines
    lines = read_intent.split("\n", -1)
    idx = lines.index { |l| l.strip == "## Insights" }
    return [] if idx.nil?

    out = []
    (idx + 1).upto(lines.length - 1) do |i|
      break if lines[i].start_with?("## ")

      out << lines[i] unless lines[i].strip.empty?
    end
    out
  end

  def test_append_to_existing_section
    write_intent("## Intent\nDemo\n\n## Insights\n2026-06-23T10:00:00Z · Why · seed — first\n")
    Insights.append_insight(@dir, "new nugget", stage: "How", author: "planner", now: T)
    lines = insight_lines
    assert_equal 2, lines.length
    assert_includes lines[0], "first"
    assert_equal "2026-06-24T08:13:05Z · How · planner — new nugget", lines[1]
  end

  def test_append_when_section_missing
    write_intent("## Intent\nDemo\n")
    Insights.append_insight(@dir, "fresh", stage: "Exec", author: "executor", now: T)
    assert_includes read_intent, "## Insights"
    lines = insight_lines
    assert_equal 1, lines.length
    assert_equal "2026-06-24T08:13:05Z · Exec · executor — fresh", lines[0]
  end

  def test_existing_order_preserved
    write_intent("## Insights\n")
    Insights.append_insight(@dir, "A", stage: "Why", author: "a", now: T)
    Insights.append_insight(@dir, "B", stage: "Why", author: "b", now: T)
    Insights.append_insight(@dir, "C", stage: "Why", author: "c", now: T)
    bodies = insight_lines.map { |l| l.split(" — ", 2).last }
    assert_equal %w[A B C], bodies
  end

  def test_deterministic_timestamp_via_injected_now
    write_intent("## Insights\n")
    Insights.append_insight(@dir, "one", stage: "Why", author: "x", now: T)
    Insights.append_insight(@dir, "two", stage: "Why", author: "x", now: T)
    insight_lines.each do |l|
      assert_includes l, "2026-06-24T08:13:05Z"
      refute_match(/\d{2}:\d{2}:\d{2}\.\d/, l, "no sub-second component")
    end
  end

  def test_creates_file_when_absent
    FileUtils.rm_f(@intent_file)
    Insights.append_insight(@dir, "born", stage: "What", author: "creator", now: T)
    assert File.exist?(@intent_file)
    assert_equal ["2026-06-24T08:13:05Z · What · creator — born"], insight_lines
  end

  def test_validator_accept
    assert Insights.valid_insight_prefix?(
      "2026-06-24T08:13:05Z · Why · plastic-brainstorming (autonomous)"
    )
  end

  def test_validator_reject_date_only
    refute Insights.valid_insight_prefix?("2026-06-22 (autonomous) note")
  end

  def test_validator_reject_missing_separator
    refute Insights.valid_insight_prefix?("2026-06-24T08:13:05Z Why me")
  end

  def test_validator_reject_missing_z
    refute Insights.valid_insight_prefix?("2026-06-24T08:13:05 · Why · me")
  end

  def test_validator_reject_subsecond
    refute Insights.valid_insight_prefix?("2026-06-24T08:13:05.123Z · Why · me")
  end
end

# CLI shell-out tests for scripts/insight-append (intent 82). Mirrors
# test/agent_report_test.rb: shell out to the real script and assert behavior.
class InsightAppendCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/insight-append", __dir__)

  def setup
    @root = Dir.mktmpdir("insight-append")
    @dir = File.join(@root, "82--demo")
    FileUtils.mkdir_p(@dir)
    @intent_file = File.join(@dir, "82--demo.md")
    File.write(@intent_file, "## Intent\nDemo\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def run_script(*args)
    IO.popen(["ruby", SCRIPT, *args], err: [:child, :out], &:read)
  end

  def test_appends_well_formed_entry
    out = run_script(@dir, "a nugget", "--stage", "How", "--author", "planner")
    assert_equal 0, $?.exitstatus
    assert_includes out, "appended:"
    content = File.read(@intent_file)
    line = content.split("\n").find { |l| l.include?("a nugget") }
    refute_nil line
    prefix = line.split(" — ", 2).first
    assert Insights.valid_insight_prefix?(prefix)
    assert_includes prefix, " · How · planner"
  end

  def test_usage_error_without_stage
    out = run_script(@dir, "a nugget", "--author", "planner")
    assert_includes out, "usage:"
    refute_equal 0, $?.exitstatus
  end

  def test_usage_error_without_author
    out = run_script(@dir, "a nugget", "--stage", "How")
    assert_includes out, "usage:"
    refute_equal 0, $?.exitstatus
  end

  def test_usage_error_without_text
    out = run_script(@dir, "--stage", "How", "--author", "planner")
    assert_includes out, "usage:"
    refute_equal 0, $?.exitstatus
  end
end
