require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/report_screen"

# Intent 317, D10: the `delivered` verb - Asked, Delivered (with a Proven-by
# column), Evidence, Needs you. The acceptance bar (post plan-review) is that
# every field traces to its named source, and the emitted Markdown's SHAPE
# (section order, headers, table columns) matches the approved plain form at
# design--delivery-reports.html:212-239 - not that the CONTENT matches the
# owner's hand-written illustration.
class ReportScreenDeliveredTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("report-screen-delivered")
    @dir = File.join(@root, "12--slug")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(name, body)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def full_fixture
    write("12--slug.md", <<~MD)
      ---
      id: "12"
      intent: "Fix regressions, tests first, shipped as alpha.5"
      sources: []
      chain: []
      created: 2026-08-30
      author: human
      tags: [demo]
      ---

      ## Intent
      Fix regressions, tests first, shipped as alpha.5
    MD
    write("spec.md", <<~MD)
      # Spec

      ## Decisions
      - D1 one
      - D2 two
      - D3 three
    MD
    write("actions/ACTION_1.md", <<~MD)
      # Action

      ### Row A — ledger captures only actionable work

      | # | Op |
      |---|---|
      | 1 | a |
      | 2 | b |
    MD
    write("savepoint.md", <<~SP)
      2026-08-30T19:00:37Z  What  12--slug.md
      2026-08-30T20:51:42Z  Done  delivered
    SP
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome

      ## Delivered
      Merged to `alpha` at **06bd20d**, released as **v2.0.0-alpha.5** (`e21809e`).

      | Row | What shipped |
      |---|---|
      | A | Ledger captures only actionable work |

      ## Verification
      - **Suite green** - 2460 runs, 12852 assertions, 0 failures.
      - a worktree at `d08a3ee` proved that commit is test-only and red.
      - Full doctor: **47 pass, 3 warn, 0 fail**.

      ## Needs you
      | N | What | Why |
      | --- | --- | --- |
      | N1 | Run /hooks in Codex | Codex hooks dormant until then |
    MD
  end

  # --- row 58: title line carries mode, duration, version, in order -----------

  def test_title_line_shape
    full_fixture
    out = ReportScreen.render_delivered(intent_dir: @dir, tag_reader: ->(_d) { "2.0.0-alpha.5" })
    lines = out.lines
    assert_equal "## ✔ 12 · Fix regressions, tests first, shipped as alpha.5 · delivered\n", lines[0]
    # mode is "not recorded" absent a live lock (this fixture has none); the
    # four segments (timestamp, mode, duration, version) must still all appear
    # in that fixed order.
    assert_match(/\A2026-08-30 20:51 UTC · not recorded · 1 h 51 min · v2\.0\.0-alpha\.5\n\z/, lines[1])
  end

  # --- row 59: Asked block --------------------------------------------------------

  def test_asked_block_shows_intent_body_and_decision_count
    full_fixture
    out = ReportScreen.render_delivered(intent_dir: @dir)
    assert_includes out, "**Asked**"
    assert_includes out, "Fix regressions, tests first, shipped as alpha.5"
    assert_includes out, "3 decisions in spec.md"
  end

  # --- row 60: Delivered table, proof beside its own row -----------------------

  def test_delivered_table_has_three_columns_proof_beside_row
    full_fixture
    out = ReportScreen.render_delivered(intent_dir: @dir)
    assert_includes out, "| Row | Detail | Proven by |"
    row_a = out.lines.find { |l| l.start_with?("| A |") }
    refute_nil row_a
    assert_includes row_a, "Ledger captures only actionable work"
    assert_includes row_a, "2 tests"
  end

  # --- row 61/62: Needs you, empty or absent ------------------------------------

  def test_needs_you_empty_renders_none_not_a_table
    write("12--slug.md", "---\nid: \"12\"\nintent: \"x\"\n---\n\n## Intent\nx\n")
    write("savepoint.md", "2026-08-30T19:00:00Z  What  12--slug.md\n2026-08-30T19:10:00Z  Done  delivered\n")
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Needs you\nNone\n")
    out = ReportScreen.render_delivered(intent_dir: @dir)
    assert_includes out, "**Needs you**\nNone"
    refute_includes out, "| N | What | Why |"
  end

  def test_no_needs_you_section_at_all_renders_none
    write("12--slug.md", "---\nid: \"12\"\nintent: \"x\"\n---\n\n## Intent\nx\n")
    write("savepoint.md", "2026-08-30T19:00:00Z  What  12--slug.md\n2026-08-30T19:10:00Z  Done  delivered\n")
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Summary\nx\n")
    out = ReportScreen.render_delivered(intent_dir: @dir)
    assert_includes out, "**Needs you**\nNone"
  end

  # --- row 63: shape golden against the approved plain form --------------------

  def test_shape_matches_the_approved_plain_form
    full_fixture
    out = ReportScreen.render_delivered(intent_dir: @dir, tag_reader: ->(_d) { "2.0.0-alpha.5" })

    headers = out.scan(/^\*\*(.+?)\*\*/).flatten
    assert_equal %w[Asked Delivered Evidence Needs\ you], headers

    assert_includes out, "| Row | Detail | Proven by |"
    assert_includes out, "| Kind | Detail | Source |"

    assert out.lines.first.start_with?("## \u2714 "), "the title line must carry the ## prefix the approved plain form uses"
    title_idx = 0
    asked_idx = out.index("**Asked**")
    delivered_idx = out.index("**Delivered**")
    evidence_idx = out.index("**Evidence**")
    needs_idx = out.index("**Needs you**")
    assert title_idx < asked_idx
    assert asked_idx < delivered_idx
    assert delivered_idx < evidence_idx
    assert evidence_idx < needs_idx
  end
end
