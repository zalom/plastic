# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "time"
require "yaml"

require_relative "../scripts/lib/runner_dispatch"
require_relative "../scripts/lib/runner_policy"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/ready_set"
require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/node_worktree"
require_relative "../scripts/lib/node_packet"
require_relative "../scripts/lib/work_graph_validator"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/guarded_append"

# A ledger double that records when `running` is about to be written, so a
# test can prove the packet exists on disk before that call happens (matrix
# row 5.18), without reaching into RunnerDispatch's own internals.
class OrderSpyLedger
  def initialize(order)
    @order = order
  end

  def append_transition(path, subject:, state:, fields: {}, now: Time.now, precondition: nil)
    @order << :running if state == "running"
    NodeLedger.append_transition(path, subject: subject, state: state, fields: fields, now: now,
                                  precondition: precondition)
  end
end

# A ledger double that refuses every `running` write outright, standing in
# for a concurrent writer that made the subject no longer ready between the
# packet build and the guarded append (matrix row 5.20).
class RefusingRunningLedger
  def append_transition(path, subject:, state:, fields: {}, now: Time.now, precondition: nil)
    return :refused if state == "running"

    NodeLedger.append_transition(path, subject: subject, state: state, fields: fields, now: now,
                                  precondition: precondition)
  end
end

# RunnerDispatch (intent 340, G7, n5): validation, policy, leases, and the
# dispatch plan. Matrix rows 5.1-5.11 and 5.18-5.34 in actions/ACTION_1.md n5
# (5.12-5.17 and 5.21 live in runner_policy_test.rb, 5.35 in
# install_sync_test.rb).
class RunnerDispatchTest < Minitest::Test
  INTENT_ID = "1"
  INTENT_SLUG = "demo"

  def setup
    @home = Dir.mktmpdir("rd-home")
    @store = File.join(@home, ".plastic", "store")
    @dir = File.join(@store, "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md"),
               "---\nid: \"#{INTENT_ID}\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
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

  def decision_body(node)
    "# #{node} - a decision\n\n## Question\nWhich approach should this take?\n"
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def build_context(worktree: nil, worktree_branch: nil, session: "test-session")
    loaded = ReadySet.load_graph(@dir)
    RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: @store, plastic_home: @home, session: session,
      worktree: worktree, worktree_branch: worktree_branch,
      graph: loaded.merge(ok: true), errors: []
    )
  end

  def git(*args, dir: @repo)
    out, err, status = Open3.capture3("git", "-C", dir, *args.map(&:to_s))
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  # A real throwaway git repo with the intent worktree already checked out
  # on the intent branch - the only honest way to test worktree provisioning
  # and merge behavior (node_worktree_test.rb's own pattern).
  def setup_real_repo
    @repo = Dir.mktmpdir("rd-repo")
    git("init", "-q", "-b", "alpha")
    git("config", "user.email", "rd@example.com")
    git("config", "user.name", "RD Test")
    git("config", "gc.auto", "0")
    File.write(File.join(@repo, "README.md"), "hi\n")
    git("add", "README.md")
    git("commit", "-q", "-m", "init")

    @intent_worktree = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
    @intent_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}"
    FileUtils.mkdir_p(File.dirname(@intent_worktree))
    git("worktree", "add", @intent_worktree, "-b", @intent_branch)
  end

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end

  # --- 5.1: the full validator runs before the first dispatch ---------------

  def test_full_validator_runs_before_first_dispatch
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    calls = 0
    spy = lambda do |dir|
      calls += 1
      WorkGraphValidator.validate(dir)
    end

    result = RunnerDispatch.dispatch(ctx, validator: spy)
    assert result[:ok], result[:errors].inspect
    assert_equal 1, calls
  end

  # --- 5.2: an invalid graph refuses dispatch outright -----------------------

  def test_invalid_graph_refuses_dispatch
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    bad_validator = ->(_dir) { { ok: false, missing: [], errors: ["synthetic validator failure"] } }
    result = RunnerDispatch.dispatch(ctx, validator: bad_validator)

    refute result[:ok]
    assert_equal "invalid_graph", result[:reason]
    assert_includes result[:errors], "synthetic validator failure"
    assert_empty result[:dispatched]
    refute File.exist?(savepoint_path), "an invalid graph must refuse to write anything"
  end

  # --- 5.3: the full validator is skipped once a node has been dispatched ---

  def test_validator_skipped_after_first_dispatch
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")
    write_savepoint(line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p",
                              model: "sonnet"))
    ctx = build_context

    spy = ->(_dir) { raise "the full validator must not run once a node has been dispatched" }
    result = RunnerDispatch.dispatch(ctx, validator: spy, limit: 2)

    assert result[:ok], result[:errors].inspect
    assert_equal ["n2"], result[:dispatched].map { |d| d[:node] }
  end

  # --- 5.4: graph.md is re-read and cycle-checked before every dispatch -----

  def test_cycle_check_runs_every_dispatch
    write_graph("- n1 needs n2\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")
    write_savepoint(line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p",
                              model: "sonnet"))
    ctx = build_context

    spy = ->(_dir) { raise "the full validator must not run once a node has been dispatched" }
    result = RunnerDispatch.dispatch(ctx, validator: spy)

    refute result[:ok]
    assert_equal "invalid_graph", result[:reason]
    assert(result[:errors].any? { |e| e =~ /cyclic/i }, result[:errors].inspect)
  end

  # --- 5.5: dispatch at most 2 - running nodes -------------------------------

  def test_dispatch_respects_concurrency_ceiling
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n- n3 needs nothing\n")
    %w[n1 n2 n3].each { |n| write_node("#{n}.md", node: n, kind: "work") }
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    assert_equal 2, result[:dispatched].length
  end

  # --- 5.6: dispatch nothing when two nodes are already running --------------

  def test_no_dispatch_when_two_running
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n- n3 needs nothing\n")
    %w[n1 n2 n3].each { |n| write_node("#{n}.md", node: n, kind: "work") }
    write_savepoint(
      line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1", model: "sonnet") +
      line("n2", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p2", model: "sonnet")
    )
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched]
  end

  # --- 5.7: dispatch in ready-set order, not the runner's own order ----------

  def test_dispatch_follows_ready_set_order
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")
    write_savepoint(line("n2", "failed_verification", holder: "h", gates: "g", reason: "suite_red"))
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx, limit: 1)
    assert result[:ok], result[:errors].inspect
    assert_equal ["n2"], result[:dispatched].map { |d| d[:node] },
                 "a retry must be ranked ahead of a fresh node"
  end

  # --- 5.8: a running sibling's file overlap blocks dispatch -----------------

  def test_file_overlap_blocks_dispatch
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", files: ["scripts/lib/shared.rb"])
    write_node("n2.md", node: "n2", kind: "work", files: ["scripts/lib/shared.rb"])
    write_savepoint(line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1",
                              model: "sonnet"))
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx, limit: 2)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched]
  end

  # --- 5.9: a ready decision node stops the loop ------------------------------

  def test_ready_decision_node_stops_loop
    write_graph("- d1 needs nothing\n- n1 needs nothing\n")
    write_node("d1.md", node: "d1", kind: "decision", body: decision_body("d1"))
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx, limit: 2)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched],
                 "a ready decision node must stop the loop before any other ready node dispatches"
    assert_equal "needs_decision", result[:status]
    refute_nil result[:stop]
    assert_equal "d1", result[:stop][:node]
    assert_equal "needs_decision", NodeLedger.status_for(savepoint_path, "d1")
  end

  # --- 5.10: the decision stop prints the exact `runner answer` command -----

  def test_decision_stop_prints_answer_command
    write_graph("- d1 needs nothing\n")
    write_node("d1.md", node: "d1", kind: "decision", body: decision_body("d1"))
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    cmd = result[:stop][:answer_command]
    assert_match(/\Arunner answer #{Regexp.escape(@dir)} --node d1 --answer /, cmd)
  end

  # --- 5.11: a node at its retry cap becomes needs_decision -------------------

  def test_node_at_retry_cap_becomes_needs_decision
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_savepoint(
      line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1", model: "sonnet") +
      line("n1", "failed_verification", holder: "h", gates: "g", reason: "suite_red") +
      line("n1", "running", holder: "h", expires: "2026-01-01T02:00:00Z", packet: "p2", model: "sonnet") +
      line("n1", "failed_verification", holder: "h", gates: "g", reason: "suite_red")
    )
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched]
    assert_equal 1, result[:parked].length
    assert_equal "n1", result[:parked].first[:node]
    assert_equal "needs_decision", NodeLedger.status_for(savepoint_path, "n1")
  end

  # --- 5.18: the packet is built before `running` is written -----------------

  def test_packet_built_before_running_line
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    order = []
    packet_builder = lambda do |**kwargs|
      order << :packet
      NodePacket.build(**kwargs)
    end

    result = RunnerDispatch.dispatch(ctx, packet_builder: packet_builder, ledger: OrderSpyLedger.new(order))
    assert_equal 1, result[:dispatched].length, result.inspect
    assert_equal [:packet, :running], order
  end

  # --- 5.19: `running` carries holder=, expires=, packet= and model= ---------

  def test_running_line_carries_required_fields
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect

    entry = NodeLedger.last_running(savepoint_path, "n1")
    refute_nil entry
    fields = entry[:fields]
    %w[holder expires packet model].each { |k| refute_nil fields[k], "running line missing #{k}=" }
  end

  # --- 5.20: a refused `running` rolls back the worktree and the packet -----

  def test_refused_running_rolls_back_side_effects
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context(worktree: @intent_worktree, worktree_branch: @intent_branch)

    result = RunnerDispatch.dispatch(ctx, ledger: RefusingRunningLedger.new)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched]

    node_path = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}--n1")
    refute Dir.exist?(node_path), "a refused running write must roll back the worktree it provisioned"
    refute Dir.glob(File.join(@dir, "packets", "n1--a*.packet")).any?,
           "a refused running write must roll back the packet it built"
  end

  # --- 5.22: the plan lists packet, model, worktree, kind and role -----------

  def test_plan_lists_packet_model_worktree_kind_role
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    entry = result[:dispatched].first
    assert_equal "n1", entry[:node]
    assert_equal "work", entry[:kind]
    assert_equal "executor", entry[:role]
    assert_equal RunnerPolicy::DEFAULT_EXECUTOR_MODEL, entry[:model]
    assert entry.key?(:worktree)
    assert entry[:packet] && File.exist?(entry[:packet])

    plan = YAML.safe_load(result[:plan])
    row = plan["dispatch"].first
    assert_equal entry[:node], row["node"]
    assert_equal entry[:kind], row["kind"]
    assert_equal entry[:role], row["role"]
    assert_equal entry[:model], row["model"]
    assert_equal entry[:packet], row["packet"]
  end

  # --- 5.23: the return contract lives in the plan, never in the packet -----

  def test_return_contract_is_in_plan_not_packet
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    packet_bytes = File.read(result[:dispatched].first[:packet])
    refute_includes packet_bytes, "RETURN CONTRACT"
    assert_includes result[:plan], "RETURN CONTRACT"
  end

  # --- 5.24: the plan is machine-readable -------------------------------------

  def test_plan_is_machine_readable
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    parsed = YAML.safe_load(result[:plan])
    assert_kind_of Hash, parsed
    assert_kind_of Array, parsed["dispatch"]
    assert_equal "n1", parsed["dispatch"].first["node"]
  end

  # --- 5.25: complete only when every declared node is terminal --------------

  def test_complete_requires_all_nodes_terminal
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_savepoint(line("n1", "done", gates: "g", commit: "c", holder: "h"))
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    assert_equal "complete", result[:status]
    assert_empty result[:dispatched]
  end

  # --- 5.25a: an empty ready set with work left reports stalled, with blockers -

  def test_empty_ready_set_with_work_left_reports_stalled
    write_graph("- verify: none reason=fixture\n- n1 needs n2\n- n2 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")
    write_savepoint(line("n2", "blocked", reason: "waiting on owner"))
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    assert_equal "stalled", result[:status]
    assert_empty result[:dispatched]
    refute_empty result[:blockers]
    assert(result[:blockers].any? { |b| b.include?("n1") })
    assert(result[:blockers].any? { |b| b.include?("n2") })
  end

  # --- 5.26: the hard attempt backstop is named, not a generic blocker -------

  def test_hard_attempt_cap_is_reported_by_name
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    content = (1..3).map do |i|
      line("n1", "running", holder: "h", expires: "2026-01-01T0#{i}:00:00Z", packet: "p#{i}", model: "sonnet") +
        line("n1", "reclaimed", holder: "h", expired: "2026-01-01T0#{i}:00:00Z")
    end.join
    write_savepoint(content)
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    assert_equal "stalled", result[:status]
    assert(result[:blockers].any? { |b| b =~ /hard attempt backstop/i && b.include?("n1") && b.include?("3/3") },
           result[:blockers].inspect)
  end

  # --- 5.27: parking at the retry cap synthesizes question= -------------------

  def test_retry_cap_needs_decision_carries_question
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_savepoint(
      line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1", model: "sonnet") +
      line("n1", "failed_verification", holder: "h", gates: "g", reason: "suite_red") +
      line("n1", "running", holder: "h", expires: "2026-01-01T02:00:00Z", packet: "p2", model: "sonnet") +
      line("n1", "failed_verification", holder: "h", gates: "g", reason: "suite_red")
    )
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    parked = result[:parked].first
    refute_nil parked
    refute_nil parked[:question]
    refute_empty parked[:question]

    entry = NodeLedger.entries(savepoint_path).select { |e| e[:subject] == "n1" }.last
    assert_equal "needs_decision", entry[:state]
    assert_equal parked[:question], entry[:fields]["question"]
  end

  # --- 5.28: the unpark command for a capped work node ------------------------

  def test_capped_node_stop_prints_unpark_command
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_savepoint(
      line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1", model: "sonnet") +
      line("n1", "failed_verification", holder: "h", gates: "g", reason: "suite_red") +
      line("n1", "running", holder: "h", expires: "2026-01-01T02:00:00Z", packet: "p2", model: "sonnet") +
      line("n1", "failed_verification", holder: "h", gates: "g", reason: "suite_red")
    )
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    cmd = result[:parked].first[:answer_command]
    assert_match(/\Arunner answer #{Regexp.escape(@dir)} --node n1 --answer /, cmd)
  end

  # --- 5.29: the packet names the node worktree and node branch --------------

  def test_packet_names_node_worktree_and_branch
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context(worktree: @intent_worktree, worktree_branch: @intent_branch)

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    entry = result[:dispatched].first

    node_path = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}--n1")
    node_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}--n1"
    assert_equal node_path, entry[:worktree]

    packet_text = File.read(entry[:packet])
    assert_includes packet_text, "worktree: #{node_path} (branch #{node_branch})"
    refute_includes packet_text, "worktree: #{@intent_worktree} (branch #{@intent_branch})"
  end

  # --- 5.30: an orphan packet (no running line for its attempt) is rebuilt --

  def test_orphan_packet_is_rebuilt_with_force
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    FileUtils.mkdir_p(File.join(@dir, "packets"))
    orphan_path = File.join(@dir, "packets", "n1--a1.packet")
    File.write(orphan_path, "stale bytes from a crashed dispatch\n")
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    assert_equal 1, result[:dispatched].length
    refute_equal "stale bytes from a crashed dispatch\n", File.read(orphan_path)
  end

  # --- 5.31: a lock refusal is a named step outcome, nothing half-dispatches -

  def test_lock_refusal_is_a_named_step_outcome
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context(session: nil)

    result = RunnerDispatch.dispatch(ctx)
    refute result[:ok]
    assert_equal "lock_not_held", result[:reason]
    assert_empty result[:dispatched]
    refute File.exist?(savepoint_path), "a lock refusal must write nothing"
    refute Dir.exist?(File.join(@dir, "packets")), "a lock refusal must build no packet"
  end

  # --- 5.32: the lock refusal prints the re-arm command -----------------------

  def test_lock_refusal_prints_rearm_command
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context(session: nil)

    result = RunnerDispatch.dispatch(ctx)
    assert_match(/\Aplastic-lock arm --intent-dir #{Regexp.escape(@dir)}\z/, result[:rearm_command])
  end

  # --- 5.33: the overlap refusal comes from ReadySet, re-checked within a step -

  def test_overlap_refusal_comes_from_ready_set
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", files: ["scripts/lib/shared.rb"])
    write_node("n2.md", node: "n2", kind: "work", files: ["scripts/lib/shared.rb"])
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx, limit: 2)
    assert result[:ok], result[:errors].inspect
    assert_equal 1, result[:dispatched].length,
                 "two file-overlapping siblings must never both dispatch in the same step"
  end

  # --- 5.34: graph.md's ## Status is re-rendered after `running` is written -

  def test_dispatch_rerenders_graph_status
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect

    rows = GraphFile.status_rows(File.join(@dir, "graph.md"))
    row = rows.find { |r| r[:node] == "n1" }
    assert_equal "running", row[:state]
  end

  # --- 10.6: a failed packet build rolls back the worktree it provisioned (M6) --

  def test_failed_packet_build_rolls_back_the_worktree
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context(worktree: @intent_worktree, worktree_branch: @intent_branch)

    failing_builder = ->(**_kwargs) { { ok: false, errors: ["synthetic packet build failure"] } }

    result = RunnerDispatch.dispatch(ctx, packet_builder: failing_builder)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched]

    node_path = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}--n1")
    refute Dir.exist?(node_path), "a failed packet build must roll back the worktree it provisioned"
  end

  # --- 10.7: a failed packet build's errors reach the step's blockers (M6) ----

  def test_failed_packet_build_names_the_node_and_the_reason
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context

    failing_builder = ->(**_kwargs) { { ok: false, errors: ["synthetic packet build failure"] } }

    result = RunnerDispatch.dispatch(ctx, packet_builder: failing_builder)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched]
    assert_equal "stalled", result[:status]
    refute_empty result[:blockers]
    assert(result[:blockers].any? { |b| b.include?("n1") && b.include?("synthetic packet build failure") },
           result[:blockers].inspect)
  end

  # --- 10.8: the node's declared budget: reaches the packet builder (M7) ------

  def test_dispatch_passes_the_nodes_declared_budget
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", budget: 123_456)
    ctx = build_context

    seen_budget = nil
    spy_builder = lambda do |**kwargs|
      seen_budget = kwargs[:budget_tokens]
      NodePacket.build(**kwargs)
    end

    result = RunnerDispatch.dispatch(ctx, packet_builder: spy_builder)
    assert result[:ok], result[:errors].inspect
    assert_equal 123_456, seen_budget
  end

  # --- 10.13: the concurrency ceiling reports queued, never stalled (M10) -----

  def test_ceiling_full_reports_queued_not_stalled
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n- n3 needs nothing\n")
    %w[n1 n2 n3].each { |n| write_node("#{n}.md", node: n, kind: "work") }
    write_savepoint(
      line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1", model: "sonnet") +
      line("n2", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p2", model: "sonnet")
    )
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched]
    assert_equal "queued", result[:status],
                 "a ready node waiting only on the concurrency ceiling must never read as stalled"
  end

  # --- 10.16: a refused running rolls back only the worktree THIS dispatch made (M13) --

  def test_rollback_keeps_a_preexisting_worktree
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    ctx = build_context(worktree: @intent_worktree, worktree_branch: @intent_branch)

    # A prior attempt's worktree, kept on disk per D7 (failed_verification
    # keeps evidence) - this dispatch must never destroy it on its OWN refusal.
    pre = NodeWorktree.provision(ctx, node: "n1", kind: "work")
    assert pre[:ok] && pre[:provisioned], pre.inspect
    node_path = pre[:path]
    assert Dir.exist?(node_path)

    result = RunnerDispatch.dispatch(ctx, ledger: RefusingRunningLedger.new)
    assert result[:ok], result[:errors].inspect
    assert_empty result[:dispatched]

    assert Dir.exist?(node_path),
           "a refused running write must never delete a worktree that existed before this dispatch"
  end

  # --- 10.21: the ceiling counts node subjects only, never Intent (minor 9) ---

  def test_ceiling_counts_only_node_subjects
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("n2.md", node: "n2", kind: "work")
    write_savepoint(
      line("Intent", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "px", model: "sonnet") +
      line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1", model: "sonnet")
    )
    ctx = build_context

    result = RunnerDispatch.dispatch(ctx, limit: 2)
    assert result[:ok], result[:errors].inspect
    assert_equal ["n2"], result[:dispatched].map { |d| d[:node] },
                 "an Intent-subject running line must not eat a dispatch slot meant for node subjects"
  end
end
