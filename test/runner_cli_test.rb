# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "time"

require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/ready_set"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/lock"

# scripts/runner (intent 340, G7, n1): the one executable with a subcommand
# table, its shared context (RunnerCore), and the two read-only queries plus
# the one write RunnerCore ships this node. Matrix rows 1.1-1.12 and
# 1.18-1.23 in actions/ACTION_1.md n1 (1.13-1.17 live in
# core_integrity_test.rb, 1.21 in install_sync_test.rb).
#
# CLI rows spawn the real script (Open3), the house pattern for
# scripts/node-transition and scripts/ready-set. Rows that exercise
# RunnerCore directly (context resolution, render_status) call the lib in
# process, the pattern test/graph_file_test.rb and test/ready_set_test.rb use.
class RunnerCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/runner", __dir__)

  def setup
    @home = Dir.mktmpdir("runner-cli-340")
    @store = File.join(@home, ".plastic", "store")
    @dir = File.join(@store, "1--demo")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "1--demo.md"), "---\nid: \"1\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixture helpers -----------------------------------------------------------

  def write_graph(graph_body, decisions: "- D1 pick approach", goal: "Ship it.")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      #{goal}

      ## Decisions
      #{decisions}

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  def write_graph_without_status(graph_body)
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      #{graph_body}
    MD
  end

  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def write_node(filename, node:, kind:, files: [], budget: 100_000, body: nil)
    body ||= "# #{node} - a node\n\n## #{node} failure-mode matrix\n#{MATRIX}\n## Steps\n1. do it\n\n## Proven by\n(filled at close)\n"
    File.write(File.join(@dir, "nodes", filename), <<~MD)
      ---
      node: #{node}
      kind: #{kind}
      files: #{files.inspect}
      budget: #{budget}
      ---
      #{body}
    MD
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  def line(subject, state, fields = nil, ts: "2026-09-10T10:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def write_lock(dir, owner:)
    File.write(File.join(dir, "delivery.lock"),
               JSON.generate("type" => "delivery", "owner_session" => owner, "delegates" => []))
  end

  def run_cli(*args, env: {})
    full_env = { "CLAUDE_CODE_SESSION_ID" => nil }.merge(env)
    Open3.capture3(full_env, RbConfig.ruby, SCRIPT, *args)
  end

  # --- 1.1: a known verb routes to its module -------------------------------------

  def test_known_verb_routes_to_module
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")

    out, err, status = run_cli("ready", @dir)
    assert_equal 0, status.exitstatus, out + err
    assert_match(/n1/, out)
  end

  # --- 1.2: an unknown verb is refused --------------------------------------------

  def test_unknown_verb_exits_2_with_usage
    out, err, status = run_cli("swep", @dir)
    assert_equal 2, status.exitstatus, out + err
    assert_match(/usage/i, err)
  end

  # --- 1.3: a non-intent path is refused ------------------------------------------

  def test_non_intent_dir_exits_2
    plain = Dir.mktmpdir("not-an-intent", @home)
    out, _err, status = run_cli("status", plain)
    assert_equal 2, status.exitstatus, out
  end

  # --- 1.4: the usage text lists only the three public verbs ---------------------

  def test_usage_lists_three_public_verbs_only
    _out, err, status = run_cli("swep", @dir)
    assert_equal 2, status.exitstatus
    assert_match(/\bstep\b/, err)
    assert_match(/\bstatus\b/, err)
    assert_match(/\banswer\b/, err)
    refute_match(/\bsweep\b/, err)
    refute_match(/\brewind\b/, err)
    refute_match(/\bready\b/, err)
  end

  # --- 1.5: the internal verbs are callable, not routed through "unknown verb" ---

  def test_internal_verbs_are_callable
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")

    out, err, status = run_cli("ready", @dir)
    assert_equal 0, status.exitstatus, out + err
    assert_match(/n1/, out)

    _out2, err2, _status2 = run_cli("rewind", @dir)
    refute_match(/unknown verb/, err2,
                 "rewind must be a recognized internal verb, not routed through the unknown-verb refusal")
  end

  # --- 1.6: a missing verb module fails only that verb ----------------------------

  # "rewind" (not "sweep") is the example undelivered verb: intent 340, G7, n2
  # shipped scripts/lib/runner_sweep.rb, so "sweep" now loads and this row's
  # premise (its module has not landed) no longer holds for it. "rewind"'s
  # module (RunnerRewind) has no node yet, so it stays the honest example of
  # the lazy-dispatch mechanism this row actually proves.
  def test_missing_module_fails_only_its_own_verb
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")

    out, err, status = run_cli("rewind", @dir)
    refute_equal 0, status.exitstatus
    refute_match(/unknown verb/, err)
    assert_match(/not yet delivered/i, out + err)

    out2, err2, status2 = run_cli("status", @dir)
    assert_equal 0, status2.exitstatus, err2
    assert_match(/n1/, out2)
  end

  # --- 1.7: RunnerCore.context resolves id/slug/store/home from disk -------------

  def test_context_resolves_id_slug_store_home
    context = RunnerCore.context(intent_dir: @dir, home: @home, env: nil)
    assert_equal "1", context.intent_id
    assert_equal "demo", context.intent_slug
    assert_equal @store, context.store
    assert_equal @home, context.plastic_home
  end

  # --- 1.8: RunnerCore.context resolves the session that holds delivery.lock -----

  def test_context_resolves_owning_session
    refute RunnerCore.context(intent_dir: @dir, home: @home, env: nil).session

    derived = Arm.derive_key(@store, "1")
    write_lock(@dir, owner: derived)
    context = RunnerCore.context(intent_dir: @dir, home: @home, env: nil)
    assert_equal derived, context.session
  end

  # --- 1.9: a missing/malformed graph.md lands in errors, never a raise ----------

  def test_context_reports_graph_error_without_raising
    File.write(File.join(@dir, "graph.md"), "# Graph: Demo\n\n## Goal\nno graph section at all\n")

    context = RunnerCore.context(intent_dir: @dir, home: @home, env: nil)
    refute_empty context.errors
    assert_equal "1", context.intent_id, "a broken graph.md must not stop the rest of the context resolving"
  end

  # --- 1.10: status prints per-node state and the last transition ----------------

  def test_status_prints_per_node_state
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")
    write_savepoint(line("n1", "running", holder: "auto-1", expires: "2026-09-10T11:00:00Z",
                              packet: "abc", model: "sonnet"))

    out, err, status = run_cli("status", @dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/n1/, out)
    assert_match(/running/, out)
    assert_match(/n2/, out)
    assert_match(/last:/, out)
  end

  # --- 1.11: status writes nothing -------------------------------------------------

  def test_status_leaves_savepoint_byte_identical
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_savepoint(line("n1", "planned"))
    before = File.read(File.join(@dir, "savepoint.md"))

    _out, err, status = run_cli("status", @dir)
    assert_equal 0, status.exitstatus, err
    assert_equal before, File.read(File.join(@dir, "savepoint.md"))
  end

  # --- 1.12: status on an intent with no ledger lines at all ---------------------

  def test_status_on_empty_ledger
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")

    out, err, status = run_cli("status", @dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/n1/, out)
    assert_match(/planned/, out)
  end

  # --- 1.18: render_status rewrites graph.md's ## Status table --------------------

  def test_render_status_rewrites_graph_status_table
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")
    write_savepoint(line("n1", "done", gates: "g1", commit: "c1", holder: "auto-1"))

    context = RunnerCore.context(intent_dir: @dir, home: @home, env: nil)
    result = RunnerCore.render_status(context)
    assert result[:ok], result[:errors].inspect

    rows = GraphFile.status_rows(File.join(@dir, "graph.md"))
    n1_row = rows.find { |r| r[:node] == "n1" }
    n2_row = rows.find { |r| r[:node] == "n2" }
    assert_equal "done", n1_row[:state]
    assert_equal "planned", n2_row[:state]
  end

  # --- 1.19: render_status covers every declared node, even with no ledger line --

  def test_render_status_covers_every_declared_node
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")

    context = RunnerCore.context(intent_dir: @dir, home: @home, env: nil)
    result = RunnerCore.render_status(context)
    assert result[:ok], result[:errors].inspect

    rows = GraphFile.status_rows(File.join(@dir, "graph.md"))
    assert_equal %w[n1 n2], rows.map { |r| r[:node] }.sort
    assert(rows.all? { |r| r[:state] == "planned" })
  end

  # --- 1.20: render_status survives a graph.md with no ## Status section ---------

  def test_render_status_creates_missing_section
    write_graph_without_status("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")

    context = RunnerCore.context(intent_dir: @dir, home: @home, env: nil)
    result = RunnerCore.render_status(context)
    assert result[:ok], result[:errors].inspect
    assert_includes File.read(File.join(@dir, "graph.md")), "## Status"
  end

  # --- 1.22: complete iff every declared node is terminal -------------------------

  def test_status_reports_stalled_not_complete_when_blocked
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_savepoint(line("n1", "blocked", reason: "waiting on owner"))

    out, err, status = run_cli("status", @dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/stalled/, out)
    refute_match(/\bcomplete\b/, out)
  end

  # --- 1.23: a stalled status prints every unfinished node's blockers ------------

  def test_status_prints_blockers_when_stalled
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")
    write_savepoint(line("n1", "blocked", reason: "waiting on owner"))

    out, err, status = run_cli("status", @dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/n1.*not eligible/, out)
    assert_match(/n2.*needs target n1/, out)
  end
end
