# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/report_screen"
require_relative "../scripts/lib/outcome_guard"

# end-intent generates outcome.md at the close before it backfills (intent
# 339, G6, n7, spec D10): a close that fails open today must never gain an
# exit 7 it did not have before this intent.
class EndIntentGeneratedOutcomeTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/end-intent", __dir__)
  SESSION = "gen-outcome-session".freeze

  def setup
    @root = Dir.mktmpdir("gen-outcome")
    @store = File.join(@root, "store")
    @tmp_bridge = File.join(@root, "tmp")
    FileUtils.mkdir_p(@store)
    FileUtils.mkdir_p(@tmp_bridge)
    @index = File.join(@root, "INDEX.md")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def run_end_intent(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @tmp_bridge }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, "--store", @store, "--id", "77",
                         "--disposition", "delivered", "--index", @index, "--no-commit",
                         "--session", SESSION, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  def base_intent_files(dir)
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "77--gate.md"), <<~MD)
      ---
      id: "77"
      intent: "Gate demo"
      sources: []
      chain: []
      created: 2026-08-31
      author: human
      tags: []
      ---

      ## Intent
      Gate demo

      ## Context
      ctx

      ## Outcome
      (the result)

      ## Insights

      ## Links
      <!-- none -->
    MD
    File.write(File.join(dir, "spec.md"), "# Spec\n\n## Decisions\n- one\n")
    File.write(File.join(dir, "plan.md"), "# Plan\n\n## Steps\n1. step\n")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n- [x] n1 the thing\n")
    File.write(File.join(dir, "delivery.lock"),
               JSON.generate("owner_session" => SESSION, "run_mode" => "auto",
                             "agent" => "plastic-enforcer"))
    File.write(@index, "# INDEX\n\n## Active\n- [77 - Gate demo](store/77--gate/77--gate.md) - demo\n\n## Completed\n")
  end

  def write_graph(dir)
    File.write(File.join(dir, "graph.md"), <<~MD)
      # Graph: Gate demo

      ## Goal
      Gate demo goal.

      ## Decisions
      - D1 demo

      ## Graph
      - n1 needs nothing

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
    File.write(File.join(dir, "nodes", "n1.md"), <<~MD)
      ---
      node: n1
      kind: work
      files: []
      budget: 1000
      ---
      # n1 - Demo unit

      ## n1 failure-mode matrix
      | Row | Operation | Failure mode | Test |
      | --- | --- | --- | --- |
      | 1.1 | a | b | c |
    MD
  end

  def write_ledger(dir, lines)
    File.write(File.join(dir, "savepoint.md"),
               "2026-08-31T09:00:00Z  What  77--gate.md\n2026-08-31T10:00:00Z  Exec  started\n#{lines.join}")
  end

  # --- 7.1 -------------------------------------------------------------------

  def test_close_generates_from_graph
    dir = File.join(@store, "77--gate")
    base_intent_files(dir)
    write_graph(dir)
    write_ledger(dir, ["2026-09-09T10:00:00Z  n1  done gates=tests commit=abc1234\n"])
    File.write(File.join(dir, "outcome.md"), "<!-- plastic:placeholder -->\n---\ndisposition: delivered|abandoned\n---\n")

    _out, status = run_end_intent
    assert_equal 0, status
    text = File.read(File.join(dir, "outcome.md"))
    assert_includes text, "| n1 |"
    refute_includes text, "backfilled from the record"
  end

  # --- 7.2 -------------------------------------------------------------------

  def test_real_outcome_is_not_overwritten
    dir = File.join(@store, "77--gate")
    base_intent_files(dir)
    write_graph(dir)
    write_ledger(dir, ["2026-09-09T10:00:00Z  n1  done gates=tests commit=abc1234\n"])
    hand_written = "---\ndisposition: delivered\n---\n# Outcome: Gate demo\n\n## Summary\nHand-written summary.\n\n## Delivered\n| Row | What |\n| --- | --- |\n| n1 | Demo unit |\n\n## Verification\n- checked\n\n## Needs you\nNone\n\n## Follow-ups\nNone\n"
    File.write(File.join(dir, "outcome.md"), hand_written)

    _out, status = run_end_intent
    assert_equal 0, status
    text = File.read(File.join(dir, "outcome.md"))
    # end-intent's own mode stamp (317a S7) touches the frontmatter even on a
    # real file; everything the human wrote must survive that stamp intact.
    assert_includes text, "Hand-written summary."
    assert_includes text, "| n1 | Demo unit |"
  end

  # --- 7.3 -------------------------------------------------------------------

  def test_intent_without_graph_uses_backfill
    dir = File.join(@store, "77--gate")
    base_intent_files(dir)
    File.write(File.join(dir, "outcome.md"), "<!-- plastic:placeholder -->\n---\ndisposition: delivered|abandoned\n---\n")
    write_ledger(dir, [])

    _out, status = run_end_intent
    assert_equal 0, status
    text = File.read(File.join(dir, "outcome.md"))
    assert_includes text, "backfilled from the record"
  end

  # --- 7.4/7.5 -----------------------------------------------------------------

  def test_close_with_no_done_node_does_not_exit_7
    dir = File.join(@store, "77--gate")
    base_intent_files(dir)
    write_graph(dir)
    write_ledger(dir, []) # n1 never ran: no done work node anywhere
    File.write(File.join(dir, "outcome.md"), "<!-- plastic:placeholder -->\n---\ndisposition: delivered|abandoned\n---\n")

    _out, status = run_end_intent
    refute_equal 7, status
    assert_equal 0, status
    text = File.read(File.join(dir, "outcome.md"))
    assert_includes text, "backfilled from the record"
  end

  def test_generated_text_is_gate_checked_before_adoption
    # Same fixture as 7.4: the generated text (no done work node) would be
    # refused by the hollow-report gate, so it must never land on disk as
    # the adopted outcome.md - the close falls through to backfill instead.
    dir = File.join(@store, "77--gate")
    base_intent_files(dir)
    write_graph(dir)
    write_ledger(dir, [])
    File.write(File.join(dir, "outcome.md"), "<!-- plastic:placeholder -->\n---\ndisposition: delivered|abandoned\n---\n")

    run_end_intent
    text = File.read(File.join(dir, "outcome.md"))
    refute_nil ReportScreen.delivered_rows(dir)
    assert_includes text, "backfilled from the record"
  end

  # --- 7.6 -------------------------------------------------------------------

  def test_generator_crash_is_fail_open
    dir = File.join(@store, "77--gate")
    base_intent_files(dir)
    write_graph(dir)
    write_ledger(dir, ["2026-09-09T10:00:00Z  n1  done gates=tests commit=abc1234\n"])
    File.write(File.join(dir, "outcome.md"), "<!-- plastic:placeholder -->\n---\ndisposition: delivered|abandoned\n---\n")

    load SCRIPT

    err = capture_io { run_generate_outcome(dir, disposition: "delivered", generator: ->(*) { raise "boom" }) }[1]
    assert_match(/outcome generation crashed/, err)
    # The placeholder is untouched - a crashing generator writes nothing.
    assert_includes File.read(File.join(dir, "outcome.md")), "plastic:placeholder"
  end
end
