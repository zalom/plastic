require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../scripts/lib/report_screen"

# Intent 317, D10/D19/D20: the record readers behind the three report screens.
# Every reader takes an explicit intent_dir (plus DI for the clock and git tag
# reading) and returns a string or an array; a missing source renders exactly
# "not recorded" (D14), never a guess or a blank.
class ReportScreenReadersTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("report-screen-readers")
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

  def base_intent_file(body_intent: "Demo intent")
    write("12--slug.md", <<~MD)
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
      #{body_intent}

      ## Context
      some context

      ## Insights
    MD
  end

  # --- row 21: asked() reads ## Intent only -----------------------------------

  def test_asked_reads_intent_section_body_only_stopping_at_next_header
    base_intent_file(body_intent: "Fix regressions, tests first, shipped as alpha.5")
    text = ReportScreen.asked(@dir)
    assert_equal "Fix regressions, tests first, shipped as alpha.5", text
    refute_includes text, "some context"
  end

  def test_asked_missing_intent_section_renders_not_recorded
    write("12--slug.md", "---\nid: \"12\"\n---\n\n## Context\nno intent section\n")
    assert_equal "not recorded", ReportScreen.asked(@dir)
  end

  # --- row 22: decision_count only counts ## Decisions bullets ----------------

  def test_decision_count_counts_only_decisions_section
    base_intent_file
    write("spec.md", <<~MD)
      # Spec

      ## Goals
      - not a decision
      - also not a decision

      ## Decisions
      - D1 first
      - D2 second
      - D3 third

      ## Alternatives Considered
      - not a decision either
    MD
    assert_equal 3, ReportScreen.decision_count(@dir)
  end

  def test_decision_count_missing_spec_renders_not_recorded
    assert_equal "not recorded", ReportScreen.decision_count(@dir)
  end

  # --- row 23: delivered_rows, table form -------------------------------------

  def test_delivered_rows_from_a_table_preserves_labels
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome

      ## Delivered
      Merged to `alpha`.

      | Row | What shipped |
      |---|---|
      | A | first thing |
      | B | second thing |
      | C | third thing |
      | E | fourth thing |
      | F | fifth thing |

      ## Verification
      - ok
    MD
    rows = ReportScreen.delivered_rows(@dir)
    assert_equal %w[A B C E F], rows.map { |r| r[:label] }
    assert_equal "first thing", rows.first[:text]
  end

  # --- row 24: delivered_rows, bullet form ------------------------------------

  def test_delivered_rows_from_bullets_also_parse
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome

      ## Delivered
      - Ledger captures only actionable work
      - Doctor catches stale registrations

      ## Verification
      - ok
    MD
    rows = ReportScreen.delivered_rows(@dir)
    assert_equal 2, rows.length
    assert_equal "1", rows[0][:label]
    assert_equal "Ledger captures only actionable work", rows[0][:text]
  end

  # --- row 25/26/27: proven_by (D19) -------------------------------------------

  def test_proven_by_matches_standalone_token_only
    write("actions/ACTION_1.md", <<~MD)
      # Action

      ### Row A — first thing

      | # | Operation | Failure mode | Test |
      |---|---|---|---|
      | 1 | x | y | z |
      | 2 | x | y | z |

      ### Row AB — a different row entirely

      | # | Operation | Failure mode | Test |
      |---|---|---|---|
      | 1 | x | y | z |
    MD
    assert_equal "2 tests", ReportScreen.proven_by(@dir, "A")
    assert_equal "1 test", ReportScreen.proven_by(@dir, "AB")
  end

  def test_proven_by_no_match_renders_not_recorded
    write("actions/ACTION_1.md", "# Action\n\n### Row Z — something\n\n| # |\n|---|\n| 1 |\n")
    assert_equal "not recorded", ReportScreen.proven_by(@dir, "Q")
  end

  def test_proven_by_counts_only_the_matched_sections_rows
    write("actions/ACTION_1.md", <<~MD)
      # Action

      ### S1 — first section

      | # | Op |
      |---|---|
      | 1 | a |
      | 2 | b |
      | 3 | c |

      ### S2 — second section

      | # | Op |
      |---|---|
      | 1 | a |
    MD
    assert_equal "3 tests", ReportScreen.proven_by(@dir, "S1")
    assert_equal "1 test", ReportScreen.proven_by(@dir, "S2")
  end

  # --- row 28: evidence_rows - suite -------------------------------------------

  def test_evidence_suite_round_trips_real_wording
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome

      ## Verification
      - **Suite green** - 2460 runs, 12852 assertions, 0 failures, run by the lead.
    MD
    rows = ReportScreen.evidence_rows(@dir)
    suite = rows.find { |r| r[:kind] == "suite" }
    refute_nil suite
    assert_equal "2460 runs · 12852 assertions · 0 failures", suite[:what]
  end

  def test_evidence_suite_absent_omits_the_row
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Verification\n- nothing here\n")
    rows = ReportScreen.evidence_rows(@dir)
    assert_nil rows.find { |r| r[:kind] == "suite" }
  end

  # --- row 29: evidence_rows - red ---------------------------------------------

  def test_evidence_red_sha_comes_from_outcome_only
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      ## Verification
      - a temporary detached worktree at `d08a3ee` proved that commit is test-only and red.
    MD
    rows = ReportScreen.evidence_rows(@dir)
    red = rows.find { |r| r[:kind] == "red" }
    refute_nil red
    assert_includes red[:what], "d08a3ee"
  end

  def test_evidence_red_absent_when_outcome_never_names_it
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Verification\n- suite green\n")
    rows = ReportScreen.evidence_rows(@dir)
    assert_nil rows.find { |r| r[:kind] == "red" }
  end

  # --- row 30: evidence_rows - ship (D20) ---------------------------------------

  def test_evidence_ship_sha_matched_anywhere_version_from_tag_reader
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      ## Delivered
      Merged to `alpha` at **06bd20d**, released as **v2.0.0-alpha.5** (`e21809e`).
    MD
    rows = ReportScreen.evidence_rows(@dir, tag_reader: ->(_dir) { "2.0.0-alpha.5" })
    ship = rows.find { |r| r[:kind] == "ship" }
    refute_nil ship
    assert_includes ship[:what], "06bd20d"
    assert_includes ship[:what], "v2.0.0-alpha.5"
  end

  def test_evidence_ship_absent_when_neither_sha_nor_version_found
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Delivered\nnothing shipped yet\n")
    rows = ReportScreen.evidence_rows(@dir, tag_reader: ->(_dir) { nil })
    assert_nil rows.find { |r| r[:kind] == "ship" }
  end

  # --- row 31: evidence_rows - doctor --------------------------------------------

  def test_evidence_doctor_counts_round_trip_including_zero_fail
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Verification\n- Full doctor: **47 pass, 3 warn, 0 fail**.\n")
    rows = ReportScreen.evidence_rows(@dir)
    doctor = rows.find { |r| r[:kind] == "doctor" }
    refute_nil doctor
    assert_equal "47 pass · 3 warn · 0 fail", doctor[:what]
  end

  # --- row 32: evidence_rows - deviates (D20) ------------------------------------

  def test_evidence_deviates_only_from_named_bullet
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      ## Verification
      - Deviation: executor rebuilt the red/green split via stash; outcome verified instead.
    MD
    rows = ReportScreen.evidence_rows(@dir)
    dev = rows.find { |r| r[:kind] == "deviates" }
    refute_nil dev
    assert_includes dev[:what], "executor rebuilt the red/green split via stash"
  end

  def test_evidence_deviates_absent_from_ordinary_prose
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Verification\n- the executor deviated on process, see below\n")
    rows = ReportScreen.evidence_rows(@dir)
    assert_nil rows.find { |r| r[:kind] == "deviates" }
  end

  # --- row 33: evidence_rows ordering ---------------------------------------------

  def test_evidence_rows_are_ordered_suite_red_ship_doctor_deviates
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      ## Delivered
      Merged to `alpha` at **06bd20d**.

      ## Verification
      - Deviation: something changed.
      - Full doctor: **1 pass, 0 warn, 0 fail**.
      - a worktree at `d08a3ee` is test-only and red.
      - **Suite green** - 10 runs, 20 assertions, 0 failures.
    MD
    rows = ReportScreen.evidence_rows(@dir, tag_reader: ->(_d) { "1.0.0" })
    assert_equal %w[suite red ship doctor deviates], rows.map { |r| r[:kind] }
  end

  # --- row 34: needs_you_rows -----------------------------------------------------

  def test_needs_you_rows_numbered_sequentially
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      ## Needs you
      | N | What | Why |
      | --- | --- | --- |
      | N1 | Run /hooks in Codex | Codex hooks dormant until then |
      | N2 | Split the delegate message | small intent |
    MD
    rows = ReportScreen.needs_you_rows(@dir)
    assert_equal %w[N1 N2], rows.map { |r| r[:n] }
    assert_equal "Run /hooks in Codex", rows[0][:what]
    assert_equal "Codex hooks dormant until then", rows[0][:why]
  end

  def test_needs_you_rows_missing_section_yields_empty_array
    write("outcome.md", "---\ndisposition: delivered\n---\n\n## Summary\nx\n")
    assert_equal [], ReportScreen.needs_you_rows(@dir)
  end

  # --- row 35: duration -------------------------------------------------------------

  def test_duration_from_first_to_last_savepoint
    write("savepoint.md", <<~SP)
      2026-08-30T19:00:37Z  What  12--slug.md
      2026-08-30T20:51:42Z  Done  delivered
    SP
    assert_equal "1 h 51 min", ReportScreen.duration(@dir)
  end

  def test_duration_under_an_hour_renders_minutes_only
    write("savepoint.md", <<~SP)
      2026-08-30T19:00:00Z  What  12--slug.md
      2026-08-30T19:35:00Z  Done  delivered
    SP
    assert_equal "35 min", ReportScreen.duration(@dir)
  end

  # --- row 36: mode (D20) -------------------------------------------------------------

  def test_mode_reads_the_live_locks_run_mode
    File.write(File.join(@dir, "delivery.lock"), { "owner_session" => "abc", "run_mode" => "auto" }.to_json)
    assert_equal "auto", ReportScreen.mode(@dir)
  end

  def test_mode_absent_lock_renders_not_recorded
    assert_equal "not recorded", ReportScreen.mode(@dir)
  end

  # --- row 37: research swap (D12) -----------------------------------------------------

  def test_research_intent_swaps_ship_for_deposits_and_verdict
    write("12--slug.md", <<~MD)
      ---
      id: "41"
      intent: "Research something"
      tags: ["research"]
      ---

      ## Intent
      Research something
    MD
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      ## Delivered
      Deposited to `resources/research-report.md`. Verdict: proceed.
    MD
    rows = ReportScreen.evidence_rows(@dir, tag_reader: ->(_d) { nil })
    refute(rows.any? { |r| r[:kind] == "ship" }, "a research intent must never carry a ship row")
  end

  # --- row 38: the "not recorded" rule, generically -------------------------------------

  def test_every_reader_with_an_absent_source_returns_the_exact_string
    assert_equal "not recorded", ReportScreen.mode(@dir)
    assert_equal "not recorded", ReportScreen.decision_count(@dir)
    write("12--slug.md", "---\nid: \"12\"\n---\n\n## Context\nx\n")
    assert_equal "not recorded", ReportScreen.asked(@dir)
  end
end
