# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "time"
require "yaml"

# scripts/runner has no .rb extension, so `require_relative` cannot resolve
# it; `load` has no such restriction and is idempotent here since Runner is
# a module, reopened harmlessly on a second load.
load File.expand_path("../scripts/runner", __dir__)
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/ready_set"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/core_integrity"

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
    Array(@script_tmp_dirs).each { |d| FileUtils.remove_entry(d) if Dir.exist?(d) }
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

  # Every shipped verb is delivered as of intent 340, G7, n6 (the last of
  # them, "rewind"), so no real verb is left whose module has not landed -
  # this row's original premise is gone. It now SYNTHESIZES that case
  # instead of relying on one: copy scripts/runner and scripts/lib/ into a
  # tmpdir, delete one verb's own lib from the copy, and prove the same
  # lazy-dispatch mechanism the real "not yet delivered" case used to
  # exercise - a verb whose module fails to load fails only that verb
  # (never "unknown verb"), and every other verb (here, `status`) keeps
  # working against the very same tree.
  def test_missing_module_fails_only_its_own_verb
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")

    broken_script = synthesize_runner_missing_lib("runner_sweep.rb")

    out, err, status = run_broken_cli(broken_script, "sweep", @dir)
    refute_equal 0, status.exitstatus
    refute_match(/unknown verb/, out + err)
    assert_match(/not yet delivered/i, out + err)

    out2, err2, status2 = run_broken_cli(broken_script, "status", @dir)
    assert_equal 0, status2.exitstatus, err2
    assert_match(/n1/, out2)
  end

  # A copy of scripts/runner plus the whole of scripts/lib/, in a fresh
  # tmpdir, with `missing_basename` deleted from the copy so a verb whose
  # own lib depends on it hits a genuine LoadError - the same failure mode
  # a not-yet-delivered node's lib produced before every real verb shipped.
  # `require_relative` inside the copied scripts/runner resolves against
  # ITS OWN path, so copying the whole lib/ directory (not just the one
  # file under test) is what keeps every OTHER verb's eager and lazy
  # requires satisfied in the copy.
  def synthesize_runner_missing_lib(missing_basename)
    tmp = Dir.mktmpdir("runner-missing-lib")
    (@script_tmp_dirs ||= []) << tmp
    FileUtils.mkdir_p(File.join(tmp, "scripts", "lib"))
    FileUtils.cp(SCRIPT, File.join(tmp, "scripts", "runner"))
    Dir.glob(File.join(File.dirname(SCRIPT), "lib", "*.rb")).each do |lib|
      FileUtils.cp(lib, File.join(tmp, "scripts", "lib", File.basename(lib)))
    end
    FileUtils.rm_f(File.join(tmp, "scripts", "lib", missing_basename))
    File.join(tmp, "scripts", "runner")
  end

  def run_broken_cli(script, *args, env: {})
    full_env = { "CLAUDE_CODE_SESSION_ID" => nil }.merge(env)
    Open3.capture3(full_env, RbConfig.ruby, script, *args)
  end

  # --- 1.7: RunnerCore.context resolves id/slug/store/home from disk -------------

  def test_context_resolves_id_slug_store_home
    context = RunnerCore.context(intent_dir: @dir, home: @home, env: nil)
    assert_equal "1", context.intent_id
    assert_equal "demo", context.intent_slug
    assert_equal @store, context.store
    assert_equal File.join(@home, ".plastic"), context.plastic_home
  end

  # --- 9.5: plastic_home resolves to the .plastic dir itself, not its parent -----

  def test_context_plastic_home_points_at_the_dot_plastic_dir
    context = RunnerCore.context(intent_dir: @dir, home: @home, env: nil)

    assert_equal File.join(@home, ".plastic"), context.plastic_home
    assert_match(%r{\.plastic\z}, context.plastic_home)
    assert_equal File.join(@home, ".plastic", "manifest.json"), File.join(context.plastic_home, "manifest.json")
  end

  # --- 9.7: the integrity check reaches THIS MACHINE's real installed manifest ---

  # An intent_dir that carries no `.plastic` path segment at all defeats
  # Worktree.home_from_store's own store-shaped resolution, so
  # RunnerCore.context falls through to the `home:` argument exactly the way
  # a sandboxed test fixture never does (Arm.home_for's own docstring: "a
  # sandboxed store never resolves to the real Dir.home") - passing the real
  # Dir.home here is what proves this row against the real installed
  # manifest.json, not a fixture one, without ever writing under it.
  def test_core_integrity_finds_the_installed_manifest
    bare_dir = Dir.mktmpdir("runner-cli-340-bare")
    (@script_tmp_dirs ||= []) << bare_dir
    intent_dir = File.join(bare_dir, "1--demo")
    FileUtils.mkdir_p(File.join(intent_dir, "nodes"))
    File.write(File.join(intent_dir, "1--demo.md"), "---\nid: \"1\"\nintent: t\n---\n\n## Intent\nbody\n")

    context = RunnerCore.context(intent_dir: intent_dir, home: Dir.home, env: nil)
    assert_equal File.join(Dir.home, ".plastic"), context.plastic_home

    result = CoreIntegrity.check(plastic_home: context.plastic_home)
    assert_nil result[:reason],
                "must reach this machine's real installed manifest.json, not report it missing: #{result.inspect}"
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

  # --- 8.4: `sweep` reaches RunnerSweep, not the unwired fall-through arm --------
  #
  # n7's dogfood (intent 340, G7, n8) found `runner sweep` printing "sweep's
  # module loaded but no dispatcher is wired up yet" and exiting 3 on every
  # call, because `dispatch_lazy` had no `when "sweep"` arm even though
  # `RunnerSweep.run` is a complete, standalone entry point. This proves the
  # real module ran: an expired `running` lease with no worktree (this
  # scratch intent names no registered project, so RunnerSweep's own
  # branch-head lookup fails open to "no new commits") is reclaimed outright.

  def test_sweep_verb_reaches_runner_sweep
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_savepoint(line("n1", "running", holder: "auto-1", expires: "2000-01-01T00:00:00Z",
                              packet: "abc", model: "sonnet"))

    out, err, status = run_cli("sweep", @dir)
    assert_equal 0, status.exitstatus, out + err
    refute_match(/no dispatcher is wired up yet/, out + err)
    assert_match(/reclaimed n1/, out)
  end

  # --- 8.5: every declared verb reaches a real dispatcher -------------------------
  #
  # A structural guard, not a feature test: it walks `Runner::VERBS` itself so
  # the next verb added to that list without a matching `when` arm in
  # `dispatch_lazy` fails here, in CI, rather than in someone's dogfood the
  # way `sweep` did.

  def test_every_declared_verb_reaches_a_dispatcher
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")

    routed_verbs = Runner::VERBS - %w[status ready]
    refute_empty routed_verbs, "this test has nothing to prove if no verb routes through dispatch_lazy"

    routed_verbs.each do |verb|
      out, err, _status = run_cli(verb, @dir)
      refute_match(/no dispatcher is wired up yet/, out + err,
                   "verb #{verb.inspect} fell through to the unwired dispatcher arm: #{out}#{err}")
    end
  end

  # --- 9.12/9.13: run_step's own lock check, before the absorb loop --------------

  # A live `running` line for n1, a return file claiming it `done`, and a
  # subprocess `step --return` call with NO session holding delivery.lock
  # (run_cli's own default env, exactly like every other row in this file).
  # B4's bug was that RunnerAbsorb wrote the transition anyway, attributed
  # to n1's rightful holder, before RunnerDispatch ever got a chance to
  # refuse - so both rows below drive the real subprocess, never the module
  # API, the same lesson n8's dogfood insight already recorded.
  def build_running_intent(holder: "auto-rightful-holder")
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_savepoint(line("n1", "running", holder: holder, expires: "2099-01-01T00:00:00Z",
                              packet: "abc", model: "sonnet"))
  end

  def write_return_file(node: "n1", status: "done", commit: "exec1234")
    doc = { "node" => node, "status" => status }
    doc["commit"] = commit if commit
    path = File.join(@home, "return-#{node}.yaml")
    File.write(path, YAML.dump(doc))
    path
  end

  def test_step_without_the_lock_writes_no_ledger_line
    build_running_intent
    return_path = write_return_file
    before = NodeLedger.entries(savepoint_path)

    out, err, status = run_cli("step", @dir, "--return", "n1=#{return_path}")

    refute_equal 0, status.exitstatus, out + err
    assert_match(/lock_not_held/, out + err, out + err)
    after = NodeLedger.entries(savepoint_path)
    assert_equal before.map { |e| e[:raw] }, after.map { |e| e[:raw] },
                 "a session holding no lock must never write a node transition"
  end

  def test_refused_step_leaves_the_ledger_unchanged
    build_running_intent
    return_path = write_return_file
    before_bytes = File.read(savepoint_path)

    _out, err, status = run_cli("step", @dir, "--return", "n1=#{return_path}")

    refute_equal 0, status.exitstatus, err
    assert_equal before_bytes, File.read(savepoint_path),
                 "the refusal message must print and the write must never happen"
  end

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end
end
