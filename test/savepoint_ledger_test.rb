require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../scripts/lib/bridge"

# Tests for the deterministic cycle-step savepoint ledger added in intent 34.
class SavepointLedgerTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("savepoint-ledger")
    @dir = File.join(@store, "34--demo")
    FileUtils.mkdir_p(@dir)
    @intent_basename = "34--demo.md"
    write("34--demo.md", "## Intent\nDemo\n")
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def write(name, body = "x\n")
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  def ledger
    f = File.join(@dir, "savepoint.md")
    File.exist?(f) ? File.read(f) : ""
  end

  def ledger_lines
    ledger.split("\n").reject(&:empty?)
  end

  # --- Task 1: savepoint_milestone -------------------------------------------

  def test_milestone_map_for_each_stage_file
    assert_equal ["What", @intent_basename], Bridge.savepoint_milestone(@dir, @intent_basename)
    assert_equal ["Why", "spec.md created"], Bridge.savepoint_milestone(@dir, "spec.md")
    assert_equal ["How", "plan.md created"], Bridge.savepoint_milestone(@dir, "plan.md")
    assert_equal ["How", "checklist.md created"], Bridge.savepoint_milestone(@dir, "checklist.md")
    assert_equal ["Exec", "outcome.md created"], Bridge.savepoint_milestone(@dir, "outcome.md")
  end

  def test_milestone_map_returns_nil_for_non_milestones
    assert_nil Bridge.savepoint_milestone(@dir, "ACTION_1.md")
    assert_nil Bridge.savepoint_milestone(@dir, "notes.md")
  end

  # --- Task 2: append_savepoint ----------------------------------------------

  def test_append_creates_formatted_line
    write("spec.md", "# Spec\nreal\n")
    t = Time.utc(2026, 6, 16, 14, 20, 0)
    assert_equal true, Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: t)
    assert_equal ["2026-06-16T14:20:00Z  Why  spec.md created"], ledger_lines
  end

  def test_append_is_idempotent_per_milestone
    write("spec.md", "# Spec\nreal\n")
    t1 = Time.utc(2026, 6, 16, 14, 20, 0)
    t2 = Time.utc(2026, 6, 16, 15, 0, 0)
    assert_equal true, Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: t1)
    assert_equal false, Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: t2)
    assert_equal 1, ledger_lines.length
  end

  def test_append_skips_sentinel_placeholder_lifecycle_file
    write("spec.md", "<!-- plastic:placeholder -->\n\nplaceholder\n")
    assert_equal false, Bridge.append_savepoint(@dir, File.join(@dir, "spec.md"), now: Time.now)
    assert_equal "", ledger
  end

  def test_append_ignores_non_milestone_files
    write("actions/ACTION_1.md")
    assert_equal false, Bridge.append_savepoint(@dir, File.join(@dir, "actions/ACTION_1.md"), now: Time.now)
    assert_equal "", ledger
  end

  def test_full_sequence_newest_at_bottom
    seq = [
      [@intent_basename, Time.utc(2026, 6, 16, 14, 0, 0)],
      ["spec.md", Time.utc(2026, 6, 16, 14, 20, 0)],
      ["plan.md", Time.utc(2026, 6, 16, 15, 10, 0)],
      ["checklist.md", Time.utc(2026, 6, 16, 15, 11, 0)],
      ["outcome.md", Time.utc(2026, 6, 16, 16, 40, 0)],
    ]
    seq.each do |name, t|
      write(name, "real #{name}\n") unless name == @intent_basename
      Bridge.append_savepoint(@dir, File.join(@dir, name), now: t)
    end
    assert_equal [
      "2026-06-16T14:00:00Z  What  #{@intent_basename}",
      "2026-06-16T14:20:00Z  Why  spec.md created",
      "2026-06-16T15:10:00Z  How  plan.md created",
      "2026-06-16T15:11:00Z  How  checklist.md created",
      "2026-06-16T16:40:00Z  Exec  outcome.md created",
    ], ledger_lines
  end

  # --- Task 3: rebuild_savepoint ---------------------------------------------

  def test_rebuild_reconstructs_from_filesystem
    write("spec.md")
    write("plan.md")
    write("checklist.md")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
    refute File.exist?(File.join(@dir, "savepoint.md"))

    count = Bridge.rebuild_savepoint(@dir)
    assert_equal 4, count # intent file + spec + plan + checklist

    milestones = ledger_lines.map { |l| l.split(/\s{2,}/)[2] }
    assert_equal [@intent_basename, "spec.md created", "plan.md created", "checklist.md created"], milestones
  end

  def test_rebuild_lines_are_chronological_by_mtime
    write("spec.md")
    write("plan.md")
    Bridge.rebuild_savepoint(@dir)
    stamps = ledger_lines.map { |l| Time.parse(l.split(/\s{2,}/)[0]) }
    assert_equal stamps.sort, stamps
  end
end
