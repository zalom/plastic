# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require "open3"
require_relative "../scripts/lib/stop_gate"
require_relative "../scripts/lib/lock"

# StopGate (intent 340b, G7c, n4, D5/D7/D8/D9): may this session stop? Matrix
# rows 4.1 to 4.22 exercise the pure module in process; rows 4.42 and 4.43
# drive the real hooks/stop launcher as a subprocess (D23). Hermetic: every
# fixture is a Dir.mktmpdir tree, nothing here touches the real ~/.plastic.
class StopGateTest < Minitest::Test
  SESSION = "auto-edc4b48edc"

  def setup
    @home = Dir.mktmpdir("stop-gate")
    @store = File.join(@home, "store")
    @intent_dir = File.join(@store, "340b--demo")
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # --- fixture helpers ---------------------------------------------------------

  def write_graph(graph_body)
    File.write(File.join(@intent_dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

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

  def write_node(filename, node:, kind: "work", files: [])
    File.write(File.join(@intent_dir, "nodes", filename), <<~MD)
      ---
      node: #{node}
      kind: #{kind}
      files: #{files.inspect}
      budget: 100000
      ---
      # #{node} - a node

      ## #{node} failure-mode matrix
      #{MATRIX}
      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD
  end

  def write_savepoint(content)
    File.write(File.join(@intent_dir, "savepoint.md"), content)
  end

  def txline(subject, state, ts: "2026-09-11T10:00:00Z", **fields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  # A single ready node: planned, no needs, nothing running against it.
  def build_ready_graph
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1")
  end

  # Every declared node terminal (row 4.11).
  def build_all_terminal_graph
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1")
    write_savepoint(txline("n1", "done", gates: "g1", commit: "abc123"))
  end

  # The only non-terminal node is already running under a live lease (row 4.13).
  def build_only_running_graph
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1")
    write_savepoint(txline("n1", "running", holder: SESSION, expires: "2026-09-11T12:00:00Z",
                           input: "n1--a1", model: "sonnet"))
  end

  # A dead-end graph: n2 needs n1, n1 is superseded, so neither is ever ready
  # again (row 4.14, the ready set is empty and the graph is stalled).
  def build_stalled_graph
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1.md", node: "n1")
    write_node("n2.md", node: "n2")
    write_savepoint(txline("n1", "superseded", by: "n3"))
  end

  def acquire_lock(run_mode: "auto", session: SESSION)
    Lock.acquire(@intent_dir, session: session, run_mode: run_mode)
  end

  def backdate_lock(seconds)
    path = Lock.path(@intent_dir)
    stamp = Time.now - seconds
    File.utime(stamp, stamp, path)
  end

  def payload(active: true, extra: {})
    { "stop_hook_active" => active }.merge(extra)
  end

  def decide(payload_h = payload, config: "true", session: SESSION, project_roots: [])
    StopGate.decide(payload: payload_h, config_stop_hook: config, session: session,
                    global_store: @store, project_roots: project_roots)
  end

  # A fully armed call: ready work, a live auto-mode lock, config on, payload
  # active. Every row below starts from this and breaks exactly one thing.
  def armed
    build_ready_graph
    acquire_lock
    decide
  end

  # --- 4.1 / 4.2: stop_hook_active -------------------------------------------

  def test_permits_when_stop_hook_active_is_false
    build_ready_graph
    acquire_lock
    result = decide(payload(active: false))
    refute result[:block]
  end

  def test_permits_when_stop_hook_active_absent
    build_ready_graph
    acquire_lock
    result = decide({})
    refute result[:block]
  end

  # --- 4.3 / 4.4 / 4.5: the config flag ---------------------------------------

  def test_permits_when_flag_is_false
    build_ready_graph
    acquire_lock
    result = decide(payload, config: "false")
    refute result[:block]
  end

  def test_flag_string_false_is_off
    # "false" is truthy in plain Ruby ("if 'false'" runs the then-branch); the
    # gate must parse it as the boolean it names, not trust its presence.
    refute StopGate.flag_true?("false")
    assert StopGate.flag_true?("true")
  end

  def test_absent_flag_is_off
    build_ready_graph
    acquire_lock
    result = decide(payload, config: nil)
    refute result[:block]
  end

  # --- 4.7 / 4.8 / 4.9: the lock -----------------------------------------------

  def test_permits_when_no_lock
    build_ready_graph
    result = decide
    refute result[:block]
  end

  def test_permits_when_lock_held_by_other_session
    build_ready_graph
    acquire_lock(session: "some-other-session")
    result = decide
    refute result[:block]
  end

  def test_permits_when_lock_expired
    build_ready_graph
    acquire_lock
    backdate_lock(Lock::TTL_SECONDS + 60)
    result = decide
    refute result[:block]
  end

  # --- 4.10: direct mode -------------------------------------------------------

  def test_permits_in_direct_mode
    build_ready_graph
    acquire_lock(run_mode: "direct")
    result = decide
    refute result[:block]
  end

  # --- 4.11 to 4.14: the fourth condition, movable work -----------------------

  def test_permits_when_all_nodes_terminal
    build_all_terminal_graph
    acquire_lock
    result = decide
    refute result[:block]
  end

  def test_permits_when_no_nodes_declared
    acquire_lock # no graph.md written at all
    result = decide
    refute result[:block]
  end

  def test_permits_when_the_only_work_is_already_running
    build_only_running_graph
    acquire_lock
    result = decide
    refute result[:block]
  end

  def test_permits_when_stalled
    build_stalled_graph
    acquire_lock
    result = decide
    refute result[:block]
  end

  # --- 4.15 to 4.18: the block path itself -------------------------------------

  def test_blocks_when_all_four_conditions_hold
    result = armed
    assert result[:block]
  end

  def test_block_output_matches_the_stop_schema
    result = armed
    assert_equal true, result[:block]
    assert_kind_of String, result[:reason]
    refute_empty result[:reason]
  end

  def test_block_reason_names_the_next_command
    result = armed
    assert_includes result[:reason], "runner step"
  end

  def test_permit_prints_nothing_and_exits_zero
    build_ready_graph
    acquire_lock
    result = decide(payload(active: false))
    assert_equal({ block: false }, result)
  end

  # --- 4.19 to 4.22: fail-open on every error ----------------------------------

  def test_permits_on_malformed_payload
    build_ready_graph
    acquire_lock
    result = decide("{not json")
    refute result[:block]
  end

  def test_permits_when_store_missing
    result = StopGate.decide(payload: payload, config_stop_hook: "true", session: SESSION,
                             global_store: File.join(@home, "does-not-exist"), project_roots: [])
    refute result[:block]
  end

  def test_permits_on_unreadable_graph
    acquire_lock
    FileUtils.mkdir_p(File.join(@intent_dir, "graph.md")) # a directory, not a file
    result = decide
    refute result[:block]
  end

  def test_permits_when_gate_raises
    build_ready_graph
    acquire_lock
    original = ActiveDelivery.method(:resolve)
    ActiveDelivery.define_singleton_method(:resolve) { |*_a, **_kw| raise "boom" }
    result = decide
    refute result[:block]
  ensure
    ActiveDelivery.define_singleton_method(:resolve, original) if original
  end
end

# Intent 340b (G7c, n4, rows 4.42/4.43, D23): hooks/stop run as a real
# subprocess, once on the block path and once on a permit path, asserting
# exact stdout. This is the one path D23 requires proven by an actual
# process launch, not just the in-process StopGate tests above.
class HookStopLauncherTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  LAUNCHER = File.join(REPO, "hooks", "stop")
  SESSION = "auto-edc4b48edc"

  def setup
    @home = Dir.mktmpdir("hook-stop-home")
    @plastic_home = File.join(@home, ".plastic")
    @store = File.join(@plastic_home, "store")
    @intent_dir = File.join(@store, "340b--demo")
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def write_config(stop_hook:)
    File.write(File.join(@plastic_home, "config.yml"),
              YAML.dump("version" => 3, "project_roots" => [], "runner" => { "stop_hook" => stop_hook }))
  end

  def write_ready_graph
    File.write(File.join(@intent_dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      - n1 needs nothing

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
    matrix = "| Operation | Failure mode | Test |\n| --- | --- | --- |\n| op | mode | a test |\n"
    File.write(File.join(@intent_dir, "nodes", "n1.md"), <<~MD)
      ---
      node: n1
      kind: work
      files: []
      budget: 100000
      ---
      # n1 - a node

      ## n1 failure-mode matrix
      #{matrix}
      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD
  end

  def acquire_lock(run_mode: "auto")
    Lock.acquire(@intent_dir, session: SESSION, run_mode: run_mode)
  end

  def run_launcher(payload_hash)
    env = { "HOME" => @home, "PLASTIC_HOME" => nil, "CLAUDE_CODE_SESSION_ID" => nil }
    Open3.capture3(env, LAUNCHER, stdin_data: JSON.generate(payload_hash))
  end

  def test_launcher_subprocess_blocks_with_valid_schema
    write_ready_graph
    acquire_lock
    write_config(stop_hook: true)

    out, err, status = run_launcher("session_id" => SESSION, "stop_hook_active" => true)
    assert_equal 0, status.exitstatus, err
    parsed = JSON.parse(out)
    assert_equal "block", parsed["decision"]
    assert_includes parsed["reason"], "runner step"
  end

  def test_launcher_subprocess_permits_silently
    write_ready_graph
    acquire_lock
    write_config(stop_hook: true)

    # stop_hook_active false alone is enough to permit, regardless of every
    # other condition being armed.
    out, err, status = run_launcher("session_id" => SESSION, "stop_hook_active" => false)
    assert_equal 0, status.exitstatus, err
    assert_equal "", out
  end
end
