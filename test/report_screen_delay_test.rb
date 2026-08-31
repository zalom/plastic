require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/report_screen"

# Intent 317, D13: the `delay` verb - the timeline as every savepoint line,
# the derived "Where the time went" line, and the Outcome line. Never narrated:
# everything traces to savepoint.md and outcome.md (D14).
class ReportScreenDelayTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("report-screen-delay")
    @dir = File.join(@root, "12--slug")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
    File.write(File.join(@dir, "12--slug.md"), <<~MD)
      ---
      id: "12"
      intent: "Demo intent"
      ---

      ## Intent
      Demo intent
    MD
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(name, body)
    File.write(File.join(@dir, name), body)
  end

  # --- row 65: every savepoint line becomes one row, lifecycle or not ----------

  def test_every_savepoint_line_becomes_a_timeline_row
    write("savepoint.md", <<~SP)
      2026-08-30T19:00:00Z  What  12--slug.md
      2026-08-30T19:20:00Z  Why  spec.md created
      2026-08-30T19:40:00Z  Review  plan REVISE
      2026-08-30T20:00:00Z  How  checklist.md created
      2026-08-30T20:10:00Z  Commit  d08a3ee 9 test files, red
      2026-08-30T20:40:00Z  Commit  cb10fd5 2446 runs, 0 failures
      2026-08-30T20:51:00Z  Done  delivered
    SP
    out = ReportScreen.render_delay(intent_dir: @dir)
    assert_equal 7, ReportScreen.delay_timeline(@dir).length
    assert_includes out, "Review"
    assert_includes out, "Commit"
  end

  # --- row 66: kind is field 2, not field 3 ------------------------------------

  def test_kind_column_is_field_two
    write("savepoint.md", "2026-08-30T19:00:00Z  Review  plan REVISE\n")
    row = ReportScreen.delay_timeline(@dir).first
    assert_equal "Review", row[:kind]
    refute_equal "plan", row[:kind]
  end

  # --- row 67: time column is HH:MM, not the full ISO stamp --------------------

  def test_time_column_is_hhmm
    write("savepoint.md", "2026-08-30T19:07:00Z  What  12--slug.md\n")
    out = ReportScreen.render_delay(intent_dir: @dir)
    assert_includes out, "19:07"
    refute_includes out, "2026-08-30T19:07:00Z"
  end

  # --- row 68: Where the time went - counts Review vs Commit correctly --------

  def test_where_the_time_went_counts_rounds_and_commits
    write("savepoint.md", <<~SP)
      2026-08-30T19:00:00Z  What  12--slug.md
      2026-08-30T19:10:00Z  Review  r1
      2026-08-30T19:20:00Z  Review  r2
      2026-08-30T19:30:00Z  Commit  c1
      2026-08-30T19:40:00Z  Commit  c2
      2026-08-30T19:50:00Z  Commit  c3
      2026-08-30T20:00:00Z  Commit  c4
    SP
    timeline = ReportScreen.delay_timeline(@dir)
    text = ReportScreen.where_time_went(timeline)
    assert_includes text, "2 round"
    assert_includes text, "4 commit"
  end

  # --- row 69/70: longest gap, adjacent rows, both kinds named ------------------

  def test_longest_gap_is_the_true_maximum_between_adjacent_rows
    write("savepoint.md", <<~SP)
      2026-08-30T19:00:00Z  What  12--slug.md
      2026-08-30T19:05:00Z  Why  spec.md created
      2026-08-30T20:05:00Z  How  checklist.md created
      2026-08-30T20:10:00Z  Done  delivered
    SP
    timeline = ReportScreen.delay_timeline(@dir)
    text = ReportScreen.where_time_went(timeline)
    assert_includes text, "60 min"
    assert_includes text, "Why"
    assert_includes text, "How"
  end

  def test_longest_gap_tie_yields_zero_and_first_occurrence_wins
    write("savepoint.md", <<~SP)
      2026-08-31T12:41:49Z  How  plan.md created
      2026-08-31T12:41:49Z  How  checklist.md created
    SP
    timeline = ReportScreen.delay_timeline(@dir)
    text = ReportScreen.where_time_went(timeline)
    assert_includes text, "0 min"
  end

  # --- row 71: Outcome line, absent renders not recorded ------------------------

  def test_outcome_line_absent_renders_not_recorded
    write("savepoint.md", "2026-08-30T19:00:00Z  What  12--slug.md\n2026-08-30T19:10:00Z  Done  delivered\n")
    out = ReportScreen.render_delay(intent_dir: @dir)
    assert_includes out, "**Outcome**   not recorded"
  end

  # --- fix 2 (post-execution review): ## Summary prose is hand-wrapped across
  # several physical lines; the first PARAGRAPH must join with single spaces,
  # and a second paragraph (after a blank line) must never bleed in.

  def test_outcome_line_joins_a_wrapped_paragraph_and_excludes_the_next_one
    write("savepoint.md", "2026-08-30T19:00:00Z  What  12--slug.md\n2026-08-30T19:10:00Z  Done  delivered\n")
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome

      ## Summary

      The first line of a paragraph
      that wraps across three
      physical lines in the source.

      A second paragraph that must never
      bleed into the Outcome line.
    MD
    out = ReportScreen.render_delay(intent_dir: @dir)
    assert_includes out, "**Outcome**   The first line of a paragraph that wraps across three physical lines in the source."
    refute_includes out, "bleed into"
  end

  # --- row 72 (A7, 315b's real case): honest about an unkept review/commit ledger

  def test_no_review_or_commit_lines_says_the_ledger_was_not_kept
    write("savepoint.md", "2026-08-30T19:00:37Z  What  12--slug.md\n2026-08-30T20:51:42Z  Done  delivered\n")
    timeline = ReportScreen.delay_timeline(@dir)
    assert_equal 2, timeline.length
    text = ReportScreen.where_time_went(timeline)
    assert_includes text, "not kept"
    refute_includes text, "0 round"
  end
end
