# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../scripts/lib/savepoint"
# Tests for Savepoint.savepoint_phantom_lines (intent 134): a pure, disk-only detector for a
# savepoint.md line that disk evidence contradicts. No bridge or session resolution, no writes.
class SavepointPhantomTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("savepoint-phantom")
    @dir = File.join(@store, "34--demo")
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "34--demo.md"), "## Intent\nDemo\n")
  end

  def teardown
    FileUtils.remove_entry(@store) if @store && Dir.exist?(@store)
  end

  def write(name, body = "real\n")
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  def write_savepoint(body)
    File.write(File.join(@dir, "savepoint.md"), body)
  end

  def reasons
    Savepoint.savepoint_phantom_lines(@dir).map(&:last)
  end

  def lines
    Savepoint.savepoint_phantom_lines(@dir).map(&:first)
  end

  # --- clean cases --------------------------------------------------------

  def test_absent_ledger_returns_empty
    refute File.exist?(File.join(@dir, "savepoint.md"))
    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  def test_clean_ledger_built_by_the_real_writer_returns_empty
    write("spec.md")
    Savepoint.append_savepoint(@dir, File.join(@dir, "spec.md"), now: Time.utc(2026, 1, 1))
    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  def test_clean_ledger_with_exec_started_and_real_prerequisites_returns_empty
    write("spec.md")
    write("plan.md")
    write("checklist.md")
    write_savepoint("2026-01-01T00:00:00Z  Exec  started\n")
    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  # --- file-landing milestone phantom -------------------------------------

  def test_flags_file_landing_line_with_no_real_file
    write_savepoint("2026-01-01T00:10:00Z  How  plan.md created\n")
    assert_equal ["2026-01-01T00:10:00Z  How  plan.md created"], lines
    assert_equal ["milestone file absent or still a sentinel placeholder"], reasons
  end

  def test_flags_file_landing_line_when_file_is_still_a_sentinel_placeholder
    write("spec.md", "#{Savepoint::PLACEHOLDER_SENTINEL}\n\nplaceholder\n")
    write_savepoint("2026-01-01T00:10:00Z  Why  spec.md created\n")
    assert_equal ["milestone file absent or still a sentinel placeholder"], reasons
  end

  def test_does_not_flag_file_landing_line_when_file_is_real
    write("spec.md")
    write_savepoint("2026-01-01T00:10:00Z  Why  spec.md created\n")
    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  # --- duplicate pair phantom ---------------------------------------------

  def test_flags_the_later_duplicate_pair
    write("spec.md")
    write_savepoint(
      "2026-01-01T00:00:00Z  Why  spec.md created\n" \
      "2026-01-01T00:05:00Z  Why  spec.md created\n"
    )
    assert_equal ["2026-01-01T00:05:00Z  Why  spec.md created"], lines
    assert_equal ["duplicate (stage, milestone) pair"], reasons
  end

  def test_distinct_pairs_sharing_milestone_text_are_not_flagged
    # "started" is shared text across stages; the (stage, milestone) PAIR differs, so both
    # are legitimate and neither is a duplicate-pair phantom (How started's own real
    # prerequisite, spec.md, is satisfied here so it is not a prerequisite phantom either).
    write("spec.md")
    write_savepoint(
      "2026-01-01T00:00:00Z  Why  started\n" \
      "2026-01-01T00:10:00Z  How  started\n"
    )
    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  # --- state-line prerequisite phantom ------------------------------------

  def test_flags_exec_started_with_no_checklist_or_plan
    write_savepoint("2026-01-01T00:00:00Z  Exec  started\n")
    assert_equal ["state line prerequisite absent on disk"], reasons
  end

  def test_flags_exec_started_with_plan_but_no_checklist
    write("plan.md")
    write_savepoint("2026-01-01T00:00:00Z  Exec  started\n")
    assert_equal ["state line prerequisite absent on disk"], reasons
  end

  def test_does_not_flag_exec_started_with_real_plan_and_checklist
    write("plan.md")
    write("checklist.md")
    write_savepoint("2026-01-01T00:00:00Z  Exec  started\n")
    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  def test_flags_how_started_with_no_real_spec
    write_savepoint("2026-01-01T00:00:00Z  How  started\n")
    assert_equal ["state line prerequisite absent on disk"], reasons
  end

  def test_does_not_flag_how_started_with_real_spec
    write("spec.md")
    write_savepoint("2026-01-01T00:00:00Z  How  started\n")
    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  def test_does_not_flag_why_started_which_has_no_extra_prerequisite
    write_savepoint("2026-01-01T00:00:00Z  Why  started\n")
    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  # --- multiple phantom classes in one ledger -----------------------------

  def test_returns_every_phantom_line_in_a_mixed_ledger
    write("spec.md") # real, so only the SECOND "spec.md created" line is a (duplicate) phantom
    write_savepoint(
      "2026-01-01T00:00:00Z  Why  spec.md created\n" \
      "2026-01-01T00:05:00Z  Why  spec.md created\n" \
      "2026-01-01T00:10:00Z  How  plan.md created\n" \
      "2026-01-01T00:15:00Z  Exec  started\n"
    )
    result = Savepoint.savepoint_phantom_lines(@dir)
    # duplicate spec.md line + phantom plan.md file-landing + Exec started prerequisite absent.
    assert_equal 3, result.length
  end
end
