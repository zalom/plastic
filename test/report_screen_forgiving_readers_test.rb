require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/report_screen"

# Intent 317a, Batch 1 (S1-S4): the forgiving readers. The 317 delivery proved
# the readers only worked on one hand-curated record (315b); every record
# written the way templates/outcome.md guided came out truncated, falsely
# "None", or falsely "0 decisions". These tests pin the forgiving contract:
# nothing invented, but everything that exists on disk survives to the screen.
class ReportScreenForgivingReadersTest < Minitest::Test
  PLACEHOLDER = "<!-- plastic:placeholder -->".freeze

  def setup
    @root = Dir.mktmpdir("forgiving-readers")
    @dir = File.join(@root, "44--slug")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
    File.write(File.join(@dir, "44--slug.md"), <<~MD)
      ---
      id: "44"
      intent: "Demo"
      sources: []
      chain: []
      created: 2026-08-31
      author: human
      tags: [demo]
      ---

      ## Intent
      Demo

      ## Context
      background

      ### Decisions

      - **D1. First ruling.** Because reasons; see D2.
      - **D2. Second ruling.** Stands alone.

      ## Insights
    MD
    File.write(File.join(@dir, "savepoint.md"),
               "2026-08-31T09:00:00Z  What  44--slug.md\n2026-08-31T10:00:00Z  Done  delivered\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(name, body)
    File.write(File.join(@dir, name), body)
  end

  def outcome(delivered: "- one thing\n", needs_you: "None\n", verification: "")
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome: demo

      ## Summary
      summary line

      ## Delivered
      #{delivered}
      ## Verification
      #{verification}
      ## Needs you
      #{needs_you}
      ## Follow-ups
      None
    MD
  end

  # --- S1: wrapped bullets join their continuation lines (matrix S1a/S1b) ---

  def test_wrapped_bullet_joins_continuation_lines
    outcome(delivered: <<~ROWS)
      - `scripts/report-screen` CLI: three verbs, `--changed`, `--ansi` with safe plain degrade,
        exit codes; record readers with the `not recorded` rule.
      - second row stays separate
    ROWS
    rows = ReportScreen.delivered_rows(@dir)
    assert_equal 2, rows.length
    assert_includes rows[0][:text], "exit codes; record readers"
    refute_includes rows[0][:text], "\n"
    assert_equal "second row stays separate", rows[1][:text]
  end

  def test_bullet_join_stops_at_blank_line_paragraph
    outcome(delivered: "- only row\n\ntrailing prose paragraph, not part of the row\n")
    rows = ReportScreen.delivered_rows(@dir)
    assert_equal 1, rows.length
    assert_equal "only row", rows[0][:text]
  end

  # --- S2: prose Needs-you is a row, never a false None (matrix S2a/S2b) ---

  def test_prose_needs_you_renders_one_row_not_none
    outcome(needs_you: <<~TXT)
      - Nothing blocks. Owner picks, when ready: (1) a paint seam;
        (2) the Codex color adapter probe.
    TXT
    rows = ReportScreen.needs_you_rows(@dir)
    assert_equal 1, rows.length
    assert_equal "N1", rows[0][:n]
    assert_includes rows[0][:what], "paint seam"
    assert_includes rows[0][:what], "Codex color adapter"
    assert_equal "not recorded", rows[0][:why]
    out = ReportScreen.render_delivered(intent_dir: @dir)
    refute_match(/\*\*Needs you\*\*\nNone/, out)
    assert_includes out, "| N1 |"
  end

  def test_literal_none_still_renders_none
    outcome(needs_you: "None\n")
    assert_equal [], ReportScreen.needs_you_rows(@dir)
    out = ReportScreen.render_delivered(intent_dir: @dir)
    assert_includes out, "**Needs you**\nNone"
  end

  def test_needs_you_table_rows_keep_working
    outcome(needs_you: "| N | What | Why |\n| --- | --- | --- |\n| N1 | pick a seam | waits on owner |\n")
    rows = ReportScreen.needs_you_rows(@dir)
    assert_equal 1, rows.length
    assert_equal "pick a seam", rows[0][:what]
    assert_equal "waits on owner", rows[0][:why]
  end

  # --- S3: decision_note fallback chain (matrix S3a/S3b/S3c) ---

  def test_prose_decisions_in_spec_count_distinct_d_tokens
    write("spec.md", <<~MD)
      # Spec

      ## Decisions

      Recorded in the intent record as D1..D16. In summary: one script (D1); plain default
      (D2); a second template (D3); D16 caps columns. D2 appears twice.
    MD
    outcome
    assert_equal "16 decisions in spec.md", ReportScreen.decision_note(@dir)
  end

  def test_bulleted_decisions_keep_exact_count_string
    write("spec.md", "# Spec\n\n## Decisions\n\n- one\n- two\n- three\n")
    outcome
    assert_equal "3 decisions in spec.md", ReportScreen.decision_note(@dir)
  end

  def test_placeholder_spec_falls_through_to_intent_record_decisions
    write("spec.md", "#{PLACEHOLDER}\n# Spec: <intent name>\n\n## Decisions\n- ...\n")
    outcome
    assert_equal "2 decisions in the intent record", ReportScreen.decision_note(@dir)
  end

  def test_no_decisions_anywhere_says_not_recorded_never_zero
    File.write(File.join(@dir, "44--slug.md"),
               File.read(File.join(@dir, "44--slug.md")).sub(/### Decisions.*## Insights/m, "## Insights"))
    write("spec.md", "#{PLACEHOLDER}\n# Spec: <intent name>\n\n## Decisions\n- ...\n")
    outcome
    assert_equal "decisions not recorded", ReportScreen.decision_note(@dir)
    out = ReportScreen.render_delivered(intent_dir: @dir)
    refute_match(/\b0 decisions/, out)
    refute_match(/\b1 decisions/, out)
  end

  # --- S4: empty evidence prints not recorded, never a bare header (matrix S4a) ---

  def test_empty_evidence_prints_not_recorded_instead_of_header_only_table
    outcome(verification: "- nothing machine-readable here\n")
    out = ReportScreen.render_delivered(intent_dir: @dir)
    assert_match(/\*\*Evidence\*\*\nnot recorded/, out)
    refute_match(/\*\*Evidence\*\*\n\| Kind \| What \| Source \|\n\| --- \| --- \| --- \|\n\n/, out)
  end
end
