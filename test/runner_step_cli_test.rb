# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "time"
require "yaml"

# scripts/runner has no .rb extension, so `require_relative` cannot resolve
# it (Ruby's require machinery only appends the .rb suffix, never accepts a
# bare extensionless path); `load` has no such restriction and is idempotent
# here since Runner is a module, not a class, reopened harmlessly on a
# second load.
load File.expand_path("../scripts/runner", __dir__)
require_relative "../scripts/lib/lock"

# scripts/runner step, end to end (intent 340, G7, n8). n7's dogfood found
# that `runner step` raises `NoMethodError: undefined method 'opt_all'` on
# every invocation and `runner sweep` falls through `dispatch_lazy`'s
# unwired arm, both because no test ever drove `scripts/runner` itself past
# argument parsing (test/runner_cli_test.rb and friends all drive the
# module API - RunnerDispatch.dispatch, RunnerSweep.run - directly). This
# file closes that gap: every test here spawns the real script as a
# subprocess (Open3), the way test/runner_cli_test.rb already does for its
# own CLI rows, so a `NoMethodError` in the child process is a test
# failure here, never a swallowed non-zero exit.
#
# Matrix rows 8.1-8.3 and 8.6-8.8 in nodes/ n8 (8.4/8.5 live in
# test/runner_cli_test.rb, which already owns the sweep/dispatch-table
# CLI rows).
class RunnerStepCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/runner", __dir__)
  SESSION = "test-session-n8"

  def setup
    @home = Dir.mktmpdir("runner-step-cli-340")
    @store = File.join(@home, ".plastic", "store")
    @dir = File.join(@store, "1--demo")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "1--demo.md"), "---\nid: \"1\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    Lock.release(@dir, session: SESSION) if @lock_armed && Dir.exist?(@dir)
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixture helpers -------------------------------------------------------

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

  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def write_node(filename, node:, kind:, files: [], budget: 100_000, body: nil)
    body ||= "# #{node} - a node\n\n## #{node} failure-mode matrix\n#{MATRIX}\n## Steps\n1. do it\n\n" \
             "## Proven by\n(filled at close)\n"
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

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end

  def savepoint_content
    File.exist?(savepoint_path) ? File.read(savepoint_path) : ""
  end

  # A one-node, ready-now work graph: n1 needs nothing, so `step` has
  # exactly one dispatchable candidate on the very first call.
  def build_ready_intent
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
  end

  # Arm the real delivery lock through Lock.acquire (scripts/plastic-lock's
  # own module), never a hand-authored JSON file: RunnerDispatch.dispatch
  # refuses to write `running` at all (row 5.31's `lock_not_held`) unless
  # `context.session` resolves to a session Lock.holds? confirms, and this
  # is the same Ruby scripts/plastic-lock arm calls to get there.
  def arm_lock
    status, = Lock.acquire(@dir, session: SESSION)
    raise "could not arm the delivery lock for the test fixture: #{status.inspect}" unless %i[acquired owned].include?(status)

    @lock_armed = true
  end

  def run_cli(*args, env: {})
    full_env = { "CLAUDE_CODE_SESSION_ID" => SESSION }.merge(env)
    Open3.capture3(full_env, RbConfig.ruby, SCRIPT, *args)
  end

  # --- 8.1/8.6: the CLI reaches RunnerDispatch, never `opt_all` -------------------

  def test_step_runs_end_to_end_on_a_scratch_intent
    build_ready_intent
    arm_lock

    out, err, status = run_cli("step", @dir)

    refute_match(/NoMethodError/, out + err, "step must never crash on opt_all: #{out}#{err}")
    refute_match(/undefined method/, out + err, out + err)
    assert_equal 0, status.exitstatus, out + err
    assert_match(/n1/, out, "a ready node must actually be dispatched: #{out}")
    assert_match(/running/, savepoint_content, "step must have written n1's running line")
  end

  # --- 8.7: step prints a dispatch plan and exits 0 for a ready node --------------

  def test_step_prints_a_dispatch_plan_for_a_ready_node
    build_ready_intent
    arm_lock

    out, _err, status = run_cli("step", @dir)
    assert_equal 0, status.exitstatus, out

    plan = YAML.safe_load(out, permitted_classes: [], aliases: false)
    refute_nil plan, "step's stdout must be the YAML dispatch plan, got: #{out.inspect}"
    assert plan.key?("return_contract"), plan.inspect
    entries = plan["dispatch"]
    refute_nil entries
    assert_equal 1, entries.length
    entry = entries.first
    assert_equal "n1", entry["node"]
    assert_equal "work", entry["kind"]
    assert_equal "executor", entry["role"]
    refute_nil entry["input"]
  end

  # --- n6, 6.3: step's text output fences the spawn block for a paste -------

  def test_step_prints_spawn_block_fenced
    build_ready_intent
    arm_lock

    out, _err, status = run_cli("step", @dir)
    assert_equal 0, status.exitstatus, out

    assert_includes out, "```", "the spawn block must be fenced so a session can paste it: #{out}"
    assert_includes out, "agent: plastic-executor", out

    plan = YAML.safe_load(out, permitted_classes: [], aliases: false)
    refute_nil plan, "step's stdout must still be the YAML dispatch plan, got: #{out.inspect}"
    assert_kind_of Array, plan["spawn"]
    refute_empty plan["spawn"]
    assert_includes plan["spawn"].first, "```"
  end

  # --- 8.8: a malformed --return pair is refused, never raised --------------------

  def test_step_refuses_a_malformed_return_pair
    build_ready_intent
    arm_lock

    out, err, status = run_cli("step", @dir, "--return", "not-a-valid-pair")

    refute_equal 0, status.exitstatus, out + err
    refute_match(/NoMethodError/, out + err, out + err)
    assert_match(/malformed/i, out + err, out + err)
    refute_match(/running/, savepoint_content,
                 "a refused malformed --return must never let dispatch write a running line")
  end

  # --- 8.2/8.3: Runner.opt_all itself, in process ---------------------------------

  def test_opt_all_returns_every_occurrence_in_order
    args = ["--return", "n1=/tmp/a.yml", "--other", "x", "--return", "n2=/tmp/b.yml"]
    assert_equal ["n1=/tmp/a.yml", "n2=/tmp/b.yml"], Runner.opt_all(args, "--return")
  end

  def test_opt_all_returns_empty_array_when_flag_absent
    assert_equal [], Runner.opt_all([], "--return")
    assert_equal [], Runner.opt_all(["--node", "n1"], "--return")
  end

  # --- 355 n3, 3.6: status prints the review fix count and the cap ----------------

  def test_status_prints_review_fix_count_and_cap
    write_graph("- n1 needs nothing\n- v1 needs n1\n- n2 needs v1\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("v1.md", node: "v1", kind: "verify")
    write_node("n2.md", node: "n2", kind: "work")

    out, err, status = run_cli("status", @dir)

    assert_equal 0, status.exitstatus, out + err
    assert_match(/^review fixes: 1 of 2$/, out)
  end
end
