require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "time"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/intent_screen"

# Intent 317: two new savepoint line kinds, Review and Commit (D5), written
# through the existing append_savepoint_line primitive so the line shape never
# changes; plus scripts/savepoint-note (D17), the writer CLI for them, which
# normalizes its --text (D21) so the dedup key cannot silently truncate.
class SavepointReviewCommitTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CLI = File.join(REPO, "scripts", "savepoint-note")

  def setup
    @store = Dir.mktmpdir("savepoint-note")
    @dir = File.join(@store, "34--demo")
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "34--demo.md"), "## Intent\nDemo\n")
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def ledger_lines
    f = File.join(@dir, "savepoint.md")
    File.exist?(f) ? File.read(f).split("\n").reject(&:empty?) : []
  end

  # --- row 1: append_review_savepoint shape ---------------------------------

  def test_append_review_savepoint_writes_review_kind
    t = Time.utc(2026, 8, 31, 12, 0, 0)
    Savepoint.append_review_savepoint(@dir, "plan REVISE", now: t)
    line = ledger_lines.last
    m = line.match(IntentScreen::SAVEPOINT_RE)
    refute_nil m, "line does not match SAVEPOINT_RE: #{line.inspect}"
    assert_equal "Review", m[2]
    assert_equal "plan REVISE", m[3]
  end

  # --- row 2: append_commit_savepoint shape ---------------------------------

  def test_append_commit_savepoint_writes_commit_kind
    t = Time.utc(2026, 8, 31, 12, 0, 0)
    Savepoint.append_commit_savepoint(@dir, "abc1234 tests red", now: t)
    line = ledger_lines.last
    m = line.match(IntentScreen::SAVEPOINT_RE)
    refute_nil m
    assert_equal "Commit", m[2]
  end

  # --- row 3: both go through append_savepoint_line's dedup/timestamp --------

  def test_both_kinds_share_the_dedup_and_timestamp_primitive
    t = Time.utc(2026, 8, 31, 12, 0, 0)
    Savepoint.append_review_savepoint(@dir, "same text", now: t)
    Savepoint.append_review_savepoint(@dir, "same text", now: t)
    assert_equal 1, ledger_lines.length, "identical text twice must dedup to one line"

    Savepoint.append_commit_savepoint(@dir, "different text", now: t)
    assert_equal 2, ledger_lines.length, "different text must add a second line"
  end

  # --- row 4 [guard]: existing lifecycle lines stay byte-identical -----------

  def test_existing_lifecycle_lines_are_unchanged_by_the_new_kinds
    t0 = Time.utc(2026, 8, 31, 11, 0, 0)
    Savepoint.append_savepoint_line(@dir, "What", "34--demo.md", t0)
    control = File.read(File.join(@dir, "savepoint.md"))

    Savepoint.append_review_savepoint(@dir, "verdict", now: Time.utc(2026, 8, 31, 11, 30, 0))
    Savepoint.append_commit_savepoint(@dir, "sha", now: Time.utc(2026, 8, 31, 11, 40, 0))

    after = File.readlines(File.join(@dir, "savepoint.md"))
    assert_equal control, after.first, "the original lifecycle line must stay byte-identical"
  end

  # --- row 5 [guard]: rebuild_savepoint never resurrects the new kinds -------

  def test_rebuild_savepoint_writes_only_file_landing_lines
    File.write(File.join(@dir, "spec.md"), "# Spec\n")
    Savepoint.append_review_savepoint(@dir, "verdict", now: Time.utc(2026, 8, 31, 11, 30, 0))
    Savepoint.append_commit_savepoint(@dir, "sha", now: Time.utc(2026, 8, 31, 11, 40, 0))

    Savepoint.rebuild_savepoint(@dir)
    rebuilt = ledger_lines
    refute(rebuilt.any? { |l| l.include?("  Review  ") }, "rebuild must not resurrect Review lines")
    refute(rebuilt.any? { |l| l.include?("  Commit  ") }, "rebuild must not resurrect Commit lines")
    assert(rebuilt.any? { |l| l.include?("What") })
    assert(rebuilt.any? { |l| l.include?("spec.md created") })
  end

  # --- row 6 [guard]: phantom detector reads a healthy ledger with both -------

  def test_phantom_detector_reports_clean_ledger_with_both_kinds
    File.write(File.join(@dir, "spec.md"), "# Spec\n")
    Savepoint.append_savepoint_line(@dir, "Why", "spec.md created", Time.utc(2026, 8, 31, 11, 20, 0))
    Savepoint.append_review_savepoint(@dir, "verdict", now: Time.utc(2026, 8, 31, 11, 30, 0))
    Savepoint.append_commit_savepoint(@dir, "sha", now: Time.utc(2026, 8, 31, 11, 40, 0))

    assert_equal [], Savepoint.savepoint_phantom_lines(@dir)
  end

  # --- row 7 [guard]: derive_stage is unaffected by the new kinds -------------

  def test_derive_stage_unaffected_by_new_kinds
    before = Savepoint.derive_stage(@dir)
    Savepoint.append_review_savepoint(@dir, "verdict", now: Time.utc(2026, 8, 31, 11, 30, 0))
    Savepoint.append_commit_savepoint(@dir, "sha", now: Time.utc(2026, 8, 31, 11, 40, 0))
    after = Savepoint.derive_stage(@dir)
    assert_equal before, after
  end

  # --- row 8: savepoint-note --text normalization (D21) -----------------------

  def test_double_space_runs_collapse_and_both_lines_land
    out, err, status = Open3.capture3("ruby", CLI, @dir, "--kind", "Commit", "--text", "abc1234  2460 runs")
    assert_equal 0, status.exitstatus, err
    out2, err2, status2 = Open3.capture3("ruby", CLI, @dir, "--kind", "Commit", "--text", "abc1234  0 failures")
    assert_equal 0, status2.exitstatus, err2

    lines = ledger_lines
    assert(lines.any? { |l| l.include?("abc1234 2460 runs") }, "first line missing: #{lines.inspect}")
    assert(lines.any? { |l| l.include?("abc1234 0 failures") }, "second line missing (dedup key must not truncate): #{lines.inspect}")
    assert_equal 2, lines.length
  end

  # --- row 9: savepoint-note --text newline is refused ------------------------

  def test_newline_in_text_exits_two_and_writes_nothing
    out, err, status = Open3.capture3("ruby", CLI, @dir, "--kind", "Review", "--text", "line one\nline two")
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_equal [], ledger_lines
  end

  # --- row 10: savepoint-note argument handling -------------------------------

  def test_bad_kind_exits_two_and_writes_nothing
    out, err, status = Open3.capture3("ruby", CLI, @dir, "--kind", "Bogus", "--text", "x")
    assert_equal 2, status.exitstatus
    assert_equal 1, err.lines.length
    assert_equal [], ledger_lines
  end

  def test_missing_text_exits_two
    out, err, status = Open3.capture3("ruby", CLI, @dir, "--kind", "Review")
    assert_equal 2, status.exitstatus
    assert_equal [], ledger_lines
  end

  def test_non_intent_directory_exits_two
    other = Dir.mktmpdir("not-an-intent")
    out, err, status = Open3.capture3("ruby", CLI, other, "--kind", "Review", "--text", "x")
    assert_equal 2, status.exitstatus
    FileUtils.rm_rf(other)
  end

  # --- intent 331f: the Report savepoint kind (S4) ----------------------------

  # F15: savepoint-note accepts --kind Report and appends a Report line through
  # the same append_savepoint_line primitive Review/Commit already use.
  def test_savepoint_note_accepts_report_kind
    out, err, status = Open3.capture3("ruby", CLI, @dir, "--kind", "Report", "--text", "state")
    assert_equal 0, status.exitstatus, err
    line = ledger_lines.last
    m = line.match(IntentScreen::SAVEPOINT_RE)
    refute_nil m, "line does not match SAVEPOINT_RE: #{line.inspect}"
    assert_equal "Report", m[2]
    assert_equal "state", m[3]
  end

  # F16: a Report line is never mistaken for a lifecycle line (What/Why/How/
  # Exec/Done), so it can never hijack stage derivation or the boarding matrix.
  def test_report_line_is_not_a_lifecycle_line
    Savepoint.append_report_savepoint(@dir, "delivered", now: Time.utc(2026, 9, 5, 12, 0, 0))
    line = ledger_lines.last
    refute IntentScreen.lifecycle_line?(line), "a Report line must never read as a lifecycle line: #{line.inspect}"

    # savepoint_milestone maps FILENAMES only, so it never answers a Report
    # pair either - the file-landing writer and the Report writer are on
    # two separate paths by construction.
    assert_nil Savepoint.savepoint_milestone(@dir, "Report")
  end
end
