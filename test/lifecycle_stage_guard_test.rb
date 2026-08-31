require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "time"
require_relative "../scripts/lib/intent_screen"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/day_summary"
require_relative "../scripts/dashboard"

# Intent 317, D6: three stage readers must not mistake a non-lifecycle savepoint
# line (Lock, Review, Commit) for the current stage. IntentScreen.savepoint_fields
# still shows the TRUE last line in the Savepoint field; only the STAGE PICK and
# the delivered scan are guarded. spawn-preamble and agent-report share the same
# bug and get the same guard (plan review finding B1). day_summary and dashboard
# deliberately keep reading the raw last line (B2/B3, no code change) - pinned
# here so that is a decision, not an accident.
class LifecycleStageGuardTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  PREAMBLE = File.join(REPO, "scripts", "spawn-preamble")
  AGENT_REPORT = File.join(REPO, "scripts", "agent-report")

  def setup
    @store = Dir.mktmpdir("lifecycle-guard")
    @dir = File.join(@store, "12--slug")
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "12--slug.md"), <<~MD)
      ---
      id: "12"
      intent: "Demo intent"
      sources: []
      chain: []
      created: 2026-08-30
      author: human
      tags: [demo]
      ---

      ## Intent
      Demo intent
    MD
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def write_ledger(lines)
    File.write(File.join(@dir, "savepoint.md"), lines.join("\n") + "\n")
  end

  HOW_LEDGER = [
    "2026-08-30T12:00:00Z  What  12--slug.md",
    "2026-08-30T12:10:02Z  How  checklist.md created",
  ].freeze

  # --- row 11: LIFECYCLE_STAGES constant --------------------------------------

  def test_lifecycle_stages_constant_is_frozen_and_exact
    assert IntentScreen::LIFECYCLE_STAGES.frozen?
    assert_equal %w[What Why How Exec Done], IntentScreen::LIFECYCLE_STAGES
  end

  # --- row 12: a trailing Lock line must not become the stage -----------------

  def test_trailing_lock_line_does_not_become_the_stage
    write_ledger(HOW_LEDGER + ["2026-08-30T13:00:00Z  Lock  takeover: session abc123"])
    fields = IntentScreen.savepoint_fields(@dir, File.read(File.join(@dir, "12--slug.md")))
    assert_equal "Exec", fields["stage"]
  end

  # --- row 13: a trailing Review or Commit line must not become the stage -----

  def test_trailing_review_line_does_not_become_the_stage
    write_ledger(HOW_LEDGER + ["2026-08-30T13:00:00Z  Review  plan REVISE"])
    fields = IntentScreen.savepoint_fields(@dir, File.read(File.join(@dir, "12--slug.md")))
    assert_equal "Exec", fields["stage"]
  end

  def test_trailing_commit_line_does_not_become_the_stage
    write_ledger(HOW_LEDGER + ["2026-08-30T13:00:00Z  Commit  abc1234 tests red"])
    fields = IntentScreen.savepoint_fields(@dir, File.read(File.join(@dir, "12--slug.md")))
    assert_equal "Exec", fields["stage"]
  end

  # --- row 14: the Savepoint field shows the TRUE last line regardless --------

  def test_savepoint_field_shows_true_last_line_while_stage_shows_lifecycle
    write_ledger(HOW_LEDGER + ["2026-08-30T13:05:00Z  Commit  abc1234 tests green"])
    fields = IntentScreen.savepoint_fields(@dir, File.read(File.join(@dir, "12--slug.md")))
    assert_equal "Exec", fields["stage"]
    assert_equal "Commit · abc1234 tests green", fields["savepoint"]
    assert_equal "2026-08-30 13:05 UTC", fields["savepoint.note"]
  end

  # --- row 15 [guard]: the delivered scan already excludes non-lifecycle -------

  def test_delivered_scan_excludes_non_lifecycle_values
    write_ledger(HOW_LEDGER + ["2026-08-30T13:00:00Z  Lock  takeover: session abc123"])
    fields = IntentScreen.savepoint_fields(@dir, File.read(File.join(@dir, "12--slug.md")))
    refute_includes fields["stage.note"], "Lock"
  end

  # --- row 16 [guard]: unchanged output for a ledger with no new kinds ---------

  def test_regression_pins_hold_for_an_ordinary_ledger
    write_ledger(HOW_LEDGER)
    fields = IntentScreen.savepoint_fields(@dir, File.read(File.join(@dir, "12--slug.md")))
    assert_equal "What, How delivered; the work is open", fields["stage.note"]
    assert_equal "Exec", fields["stage"]
    assert_equal "How · checklist.md created", fields["savepoint"]
    assert_equal "2026-08-30 12:10 UTC", fields["savepoint.note"]
  end

  def test_regression_pin_done_ledger
    write_ledger(HOW_LEDGER + ["2026-08-30T14:00:00Z  Done  delivered"])
    fields = IntentScreen.savepoint_fields(@dir, File.read(File.join(@dir, "12--slug.md")))
    assert_equal "Done", fields["stage"]
  end

  # --- row 17: spawn-preamble's Current stage: line ---------------------------

  def test_spawn_preamble_names_the_last_lifecycle_line
    write_ledger(HOW_LEDGER + ["2026-08-30T13:10:00Z  Commit  abc1234 2460 runs"])
    out, err, status = Open3.capture3("ruby", PREAMBLE, @dir)
    assert_equal 0, status.exitstatus, err
    line = out.lines.find { |l| l.start_with?("Current stage:") }
    refute_nil line
    assert_includes line, "How  checklist.md created"
    refute_includes line, "Commit"
  end

  # --- row 18: agent-report's Stage: line -------------------------------------

  def test_agent_report_names_the_last_lifecycle_line
    write_ledger(HOW_LEDGER + ["2026-08-30T13:10:00Z  Commit  abc1234 2460 runs"])
    out, err, status = Open3.capture3("ruby", AGENT_REPORT, @dir)
    assert_equal 0, status.exitstatus, err
    line = out.lines.find { |l| l.start_with?("Stage:") }
    refute_nil line
    assert_includes line, "How  checklist.md created"
    refute_includes line, "Commit"
  end

  # --- row 19: day_summary.last_savepoint_line, deliberately unguarded --------

  def test_day_summary_last_savepoint_line_shows_the_raw_last_line
    write_ledger(HOW_LEDGER + ["2026-08-30T13:10:00Z  Commit  abc1234 2460 runs"])
    text = DaySummary.last_savepoint_line(@dir)
    assert_includes text, "Commit"
    assert_includes text, "abc1234 2460 runs"
  end

  # --- row 20: dashboard.rb's last_accessed_at / savepoint_shows_progress? ----

  def test_dashboard_reader_functions_are_unaffected_by_commit_lines
    write_ledger(HOW_LEDGER + ["2026-08-30T13:10:00Z  Commit  abc1234 2460 runs"])
    path = File.join(@dir, "savepoint.md")
    assert_equal "2026-08-30T13:10:00Z", last_accessed_at(@dir, "2026-08-30")
    assert_equal true, savepoint_shows_progress?(path)
    assert_nil done_timestamp(@dir)
  end
end
