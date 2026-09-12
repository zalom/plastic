# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/intent_screen"
require_relative "../scripts/lib/node_progress"

# Intent 337a, n1: the graph-era progress reader. Matrix rows 1.1-1.16 in
# actions/ACTION_1.md (row 1.17 lives in install_sync_test.rb). Hermetic:
# Dir.mktmpdir fixtures, no environment read.
class NodeProgressTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("node-progress")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def intent_dir(name)
    dir = File.join(@dir, name)
    FileUtils.mkdir_p(dir)
    dir
  end

  def write_graph(dir, node_ids)
    lines = node_ids.map { |id| "- #{id} needs nothing" }
    File.write(File.join(dir, "graph.md"), "## Graph\n#{lines.join("\n")}\n")
  end

  def write_nodes_dir(dir, node_ids)
    nodes_dir = File.join(dir, "nodes")
    FileUtils.mkdir_p(nodes_dir)
    node_ids.each { |id| File.write(File.join(nodes_dir, "#{id}.md"), "# #{id}\n") }
  end

  def graph_intent(name, node_ids)
    dir = intent_dir(name)
    write_graph(dir, node_ids)
    write_nodes_dir(dir, node_ids)
    dir
  end

  def write_savepoint(dir, text)
    File.write(File.join(dir, "savepoint.md"), text)
  end

  def write_outcome(dir)
    File.write(File.join(dir, "outcome.md"), "## Delivered\n- shipped\n")
  end

  def done_line(subject, extra = {})
    NodeLedger.transition_line(subject: subject, state: "done",
                                fields: { gates: "green", verdict: "ok" }.merge(extra))
  end

  def running_line(subject, extra = {})
    NodeLedger.transition_line(subject: subject, state: "running",
                                fields: { holder: "auto-a", expires: "2026-09-12T19:00:00Z",
                                          packet: "abc123", model: "sonnet" }.merge(extra))
  end

  # --- 1.1 / 1.2: graph-era gate -----------------------------------------------

  def test_intent_without_graph_md_is_not_graph_era
    dir = intent_dir("40--no-graph")
    write_nodes_dir(dir, %w[n1])
    assert_nil NodeProgress.fields(dir)
  end

  def test_graph_md_without_nodes_dir_is_not_graph_era
    dir = intent_dir("41--no-nodes-dir")
    write_graph(dir, %w[n1])
    assert_nil NodeProgress.fields(dir)
  end

  # --- 1.3: declared nodes come from ## Graph, never Dir ------------------------

  def test_declared_nodes_come_from_the_graph_section_not_the_directory
    dir = graph_intent("42--leftover-file", %w[n1 n2])
    File.write(File.join(dir, "nodes", "n3.md"), "# n3\n")
    write_savepoint(dir, [done_line("n1"), done_line("n2")].join)
    fields = NodeProgress.fields(dir)
    assert_equal "2", fields["progress.total"]
    assert_equal "2", fields["progress.done"]
    assert_equal "all nodes done", fields["progress.note"]
  end

  # --- 1.4: last non-torn line per subject, in file order -----------------------
  #
  # Ledger compatibility fixture (intent 340b harness=, intent 355 calls=):
  # the n2 line below is exactly the shape those two intents add. NodeLedger
  # reads it via #status without raising; whether it counts as running or
  # torn is NodeLedger's call, reported as a finding rather than worked
  # around here.

  def test_state_is_the_last_non_torn_line_per_subject
    dir = graph_intent("43--last-non-torn", %w[n1 n2])
    write_savepoint(dir, [
      running_line("n1"),
      "2026-09-12T19:15:00Z  n1  running  holder=auto-a\n",
      "2026-09-12T20:00:00Z  n2  running  holder=auto-x model=sonnet harness=claude calls=41\n",
      "2026-09-12T20:30:00Z  n1  done  gates=green commit=abc1234 harness=claude calls=52\n",
    ].join)
    fields = NodeProgress.fields(dir)
    assert_equal "2", fields["progress.total"]
    assert_equal "1", fields["progress.done"], "n1's last non-torn line is done, not the torn line in between"
  end

  # --- 1.5: undeclared subjects never join the denominator -----------------------

  def test_undeclared_subjects_are_ignored
    dir = graph_intent("44--undeclared-subjects", %w[n1 n2])
    write_savepoint(dir, [
      "2026-09-12T18:00:00Z  Commit  abc1234 landed\n",
      "2026-09-12T18:05:00Z  Exec  outcome.md created\n",
      "2026-09-12T18:10:00Z  Done  delivered\n",
      done_line("n1"),
    ].join)
    fields = NodeProgress.fields(dir)
    assert_equal "2", fields["progress.total"]
    assert_equal "1", fields["progress.done"]
  end

  # --- 1.6: a declared node with no line at all is planned, never raises --------

  def test_declared_node_with_no_line_counts_as_planned
    dir = graph_intent("45--no-line", %w[n1 n2])
    write_savepoint(dir, done_line("n1"))
    fields = NodeProgress.fields(dir)
    assert_equal "2", fields["progress.total"]
    assert_equal "1", fields["progress.done"]
    assert_equal "1 nodes open", fields["progress.note"]
  end

  # --- 1.7: running nodes counted in the note ------------------------------------
  #
  # Carries the same 340b/355 fixture line as 1.4 (n2, torn) alongside a
  # genuinely valid running line (n3), so the note's running count is proven
  # against real data, not just the torn compatibility line.

  def test_running_nodes_are_counted_in_the_note
    dir = graph_intent("46--running-note", %w[n1 n2 n3])
    write_savepoint(dir, [
      "2026-09-12T18:00:00Z  n1  done  gates=green commit=abc1234 harness=claude calls=52\n",
      "2026-09-12T20:00:00Z  n2  running  holder=auto-x model=sonnet harness=claude calls=41\n",
      running_line("n3"),
    ].join)
    fields = NodeProgress.fields(dir)
    assert_equal "3", fields["progress.total"]
    assert_equal "1", fields["progress.done"]
    assert_equal "2 nodes open, 1 running", fields["progress.note"]
  end

  # --- 1.8: reclaimed resolves to planned ----------------------------------------

  def test_reclaimed_resolves_to_planned
    dir = graph_intent("47--reclaimed", %w[n1 n2])
    write_savepoint(dir, NodeLedger.transition_line(subject: "n1", state: "reclaimed",
                                                      fields: { holder: "auto-a", expired: "2026-09-12T18:00:00Z" }))
    fields = NodeProgress.fields(dir)
    assert_equal "0", fields["progress.done"]
    assert_equal "2 nodes open", fields["progress.note"]
  end

  # --- 1.9: delivered, no done lines at all, is inferred all-done ---------------

  def test_delivered_intent_with_no_done_lines_is_inferred_all_done
    dir = graph_intent("48--inferred", %w[n1 n2 n3])
    write_outcome(dir)
    write_savepoint(dir, "2026-09-12T18:00:00Z  Done  delivered\n")
    fields = NodeProgress.fields(dir)
    assert_equal "3", fields["progress.total"]
    assert_equal "3", fields["progress.done"]
    assert_equal "inferred: delivered before the node ledger", fields["progress.note"]
  end

  # --- 1.10: delivered proven by outcome.md + INDEX ## Completed ----------------

  def test_index_completed_proves_delivered
    dir = graph_intent("49--index-completed", %w[n1 n2])
    write_outcome(dir)
    File.write(File.join(@dir, "INDEX.md"), <<~MD)
      # INDEX

      ## Completed
      - [49 - index completed sample](store/49--index-completed/49--index-completed.md) - delivered
    MD
    fields = NodeProgress.fields(dir, store_root: @dir)
    assert_equal "2", fields["progress.done"]
    assert_equal "inferred: delivered before the node ledger", fields["progress.note"]
  end

  # --- 1.11: delivered proven by outcome.md + a Done savepoint line -------------

  def test_done_savepoint_line_proves_delivered_without_store_root
    dir = graph_intent("50--done-line", %w[n1 n2])
    write_savepoint(dir, "2026-09-12T18:00:00Z  Done  delivered\n")
    # a Done line alone, with no outcome.md, is not proof of delivery
    refute_equal "2", NodeProgress.fields(dir)["progress.done"]

    write_outcome(dir)
    fields = NodeProgress.fields(dir, store_root: nil)
    assert_equal "2", fields["progress.done"]
    assert_equal "inferred: delivered before the node ledger", fields["progress.note"]
  end

  # --- 1.12: undelivered, no done lines, counts zero, never inferred ------------

  def test_undelivered_intent_with_no_done_lines_counts_zero
    dir = graph_intent("51--undelivered", %w[n1 n2 n3])
    fields = NodeProgress.fields(dir)
    assert_equal "0", fields["progress.done"]
    assert_equal "3", fields["progress.total"]
    assert_equal "3 nodes open", fields["progress.note"]
  end

  # --- 1.13: partial done lines are never inferred -------------------------------

  def test_partial_done_lines_are_never_inferred
    dir = graph_intent("52--partial-done", %w[n1 n2 n3])
    write_outcome(dir)
    write_savepoint(dir, [done_line("n1"), "2026-09-12T18:10:00Z  Done  delivered\n"].join)
    fields = NodeProgress.fields(dir)
    assert_equal "1", fields["progress.done"]
    assert_equal "3", fields["progress.total"]
    assert_equal "2 nodes open", fields["progress.note"]
  end

  # --- 1.14: unit is nodes, bar matches IntentScreen::BAR_WIDTH -----------------

  def test_unit_is_nodes_and_bar_matches_intent_screen_width
    dir = graph_intent("53--bar-width", %w[n1 n2 n3 n4])
    write_savepoint(dir, [done_line("n1"), done_line("n2")].join)
    fields = NodeProgress.fields(dir)
    assert_equal "nodes", fields["progress.unit"]
    assert_equal IntentScreen::BAR_WIDTH, fields["progress.bar"].length
    on = (2 * IntentScreen::BAR_WIDTH) / 4
    expected = (IntentScreen::ON * on) + (IntentScreen::OFF * (IntentScreen::BAR_WIDTH - on))
    assert_equal expected, fields["progress.bar"]
  end

  # --- 1.15: note text, exactly, per case ----------------------------------------

  def test_note_text_per_case
    all_done = graph_intent("54--all-done", %w[n1 n2])
    write_savepoint(all_done, [done_line("n1"), done_line("n2")].join)
    assert_equal "all nodes done", NodeProgress.fields(all_done)["progress.note"]

    open_only = graph_intent("55--open-only", %w[n1 n2 n3])
    assert_equal "3 nodes open", NodeProgress.fields(open_only)["progress.note"]

    with_running = graph_intent("56--with-running", %w[n1 n2])
    write_savepoint(with_running, running_line("n1"))
    assert_equal "2 nodes open, 1 running", NodeProgress.fields(with_running)["progress.note"]

    inferred = graph_intent("57--inferred-note", %w[n1 n2])
    write_outcome(inferred)
    write_savepoint(inferred, "2026-09-12T18:00:00Z  Done  delivered\n")
    assert_equal "inferred: delivered before the node ledger", NodeProgress.fields(inferred)["progress.note"]
  end

  # --- 1.16: broken inputs never raise -------------------------------------------

  def test_broken_inputs_never_raise
    malformed = intent_dir("58--malformed-graph")
    File.write(File.join(malformed, "graph.md"), "not a real graph file at all\n")
    write_nodes_dir(malformed, %w[n1])
    assert_nil NodeProgress.fields(malformed)

    no_nodes_declared = intent_dir("59--no-nodes-declared")
    write_graph(no_nodes_declared, [])
    write_nodes_dir(no_nodes_declared, %w[n1])
    assert_nil NodeProgress.fields(no_nodes_declared)

    torn_ledger = graph_intent("60--torn-ledger", %w[n1])
    write_savepoint(torn_ledger, "2026-09-12T18:00:00Z  n1  running  holder=\n")
    refute_nil NodeProgress.fields(torn_ledger)

    no_savepoint = graph_intent("61--no-savepoint", %w[n1])
    FileUtils.rm_f(File.join(no_savepoint, "savepoint.md"))
    refute_nil NodeProgress.fields(no_savepoint)

    bad_utf8 = graph_intent("62--bad-utf8", %w[n1])
    File.open(File.join(bad_utf8, "graph.md"), "wb") { |f| f.write("## Graph\n- n1 needs nothing \xFF\xFE\n") }
    NodeProgress.fields(bad_utf8) # must not raise
  end
end
