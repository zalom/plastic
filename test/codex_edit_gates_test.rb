# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"
require_relative "../scripts/lib/codex_edit_gates"
require_relative "../scripts/lib/apply_patch_envelope"
require_relative "../scripts/lib/worktree"

# CodexEditGates driven IN-PROCESS (no subprocess), which is what makes each
# gate provable in isolation now that the per-gate registrations are gone
# (intent 251, spec D15 part 3). Follows the hermeticity rules test/
# codex_hooks_test.rb already uses: inject PLASTIC_TMP, a fake HOME, and never
# write with the ambient session id. Bridge.tmp_dir reads ENV["PLASTIC_TMP"]
# at call time (scripts/lib/bridge.rb:54-57), so any in-process Bridge call
# (Bridge.arm_auto below) needs that env var set BEFORE the call, not merely
# passed to a later subprocess's env hash (ACTION_1 found this the hard way).
class CodexEditGatesTest < Minitest::Test
  Op = ApplyPatchEnvelope::Op

  def setup
    @root = Dir.mktmpdir("codex-edit-gates")
    @store = File.join(@root, "store")
    FileUtils.mkdir_p(@store)
    @bridge_tmp = Dir.mktmpdir("codex-edit-gates-tmp")
    @fake_home = Dir.mktmpdir("codex-edit-gates-home")
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    @saved_home = ENV["HOME"]
    ENV["PLASTIC_TMP"] = @bridge_tmp
    ENV["HOME"] = @fake_home
    ENV.delete("CLAUDE_CODE_SESSION_ID")

    # Neutralize the real provision (intent 108 hermeticity fix): unstubbed,
    # arm's provision would plant a store worktree in the LIVE ~/.plastic.
    @real_provision = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
  end

  def teardown
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@bridge_tmp)
    FileUtils.rm_rf(@fake_home)
    @saved_session.nil? ? ENV.delete("CLAUDE_CODE_SESSION_ID") : ENV["CLAUDE_CODE_SESSION_ID"] = @saved_session
    @saved_plastic_tmp.nil? ? ENV.delete("PLASTIC_TMP") : ENV["PLASTIC_TMP"] = @saved_plastic_tmp
    @saved_home.nil? ? ENV.delete("HOME") : ENV["HOME"] = @saved_home
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
  end

  def silence_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  def payload(session_id: "", tool_name: "apply_patch")
    { "session_id" => session_id, "tool_name" => tool_name }
  end

  def malformed_intent_content
    "---\nid: \"1\"\n---\n\n## Intent\nDemo\n"
  end

  # ---- create-gate add-only rule (spec D2) ----

  def test_create_gate_runs_on_an_add_op
    path = File.join(@store, "1--demo", "1--demo.md")
    op = Op.new(op: :add, path: path, added_content: malformed_intent_content)
    ctx = CodexEditGates.context_for(payload, op)
    outcome = CodexEditGates.create_gate(ctx, op)
    refute_nil outcome, "an Add of malformed intent content must be denied"
    assert_equal :stderr, outcome.shape
    assert_includes outcome.lines.join(" "), "PLASTIC CREATE GATE"
  end

  def test_create_gate_defers_on_an_update_op
    path = File.join(@store, "1--demo", "1--demo.md")
    op = Op.new(op: :update, path: path, added_content: malformed_intent_content)
    ctx = CodexEditGates.context_for(payload, op)
    outcome = CodexEditGates.create_gate(ctx, op)
    assert_nil outcome, "Update ops must defer to the PostToolUse backstop (add-only rule, spec D2)"
  end

  def test_create_gate_defers_on_a_delete_op
    path = File.join(@store, "1--demo", "1--demo.md")
    op = Op.new(op: :delete, path: path, added_content: nil)
    ctx = CodexEditGates.context_for(payload, op)
    outcome = CodexEditGates.create_gate(ctx, op)
    assert_nil outcome, "Delete ops must defer, and must not raise on a nil added_content"
  end

  # ---- context_for (spec D1, D6) ----

  def test_context_carries_the_codex_harness
    path = File.join(@store, "some", "path.md")
    op = Op.new(op: :update, path: path, added_content: "x")
    ctx = CodexEditGates.context_for(payload, op)
    assert_equal "codex", ctx.harness
    assert_equal path, ctx.gate_path
    assert_equal path, ctx.file_path
    assert_equal path, ctx.savepoint_path
  end

  def test_context_content_is_always_a_string
    op = Op.new(op: :delete, path: "/tmp/x.md", added_content: nil)
    ctx = CodexEditGates.context_for(payload, op)
    assert_equal "", ctx.content
    refute_nil ctx.content
  end

  def test_context_falls_back_to_the_environment_session
    op = Op.new(op: :update, path: "/tmp/x.md", added_content: "x")
    ctx = CodexEditGates.context_for(payload(session_id: ""), op, env: { "CLAUDE_CODE_SESSION_ID" => "env-session" })
    assert_equal "env-session", ctx.session

    ctx2 = CodexEditGates.context_for(payload(session_id: ""), op, env: {})
    assert_nil ctx2.session
  end

  # ---- two-pass dispatch (spec D3) ----

  def test_savepoint_runs_for_every_op_even_when_a_later_op_denies
    intent_dir_52 = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir_52)
    File.write(File.join(intent_dir_52, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir_52, "spec.md"), "spec\n") # stage Why, pre-How

    project_file = File.join(@root, "code", "bad.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    silence_stderr do
      Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir_52, store: @store, name: "demo")
    end

    intent_dir_81 = File.join(@store, "81--x")
    FileUtils.mkdir_p(intent_dir_81)
    File.write(File.join(intent_dir_81, "81--x.md"), "## Intent\nx\n")
    spec_81 = File.join(intent_dir_81, "spec.md")

    op1 = Op.new(op: :update, path: project_file, added_content: "puts 2\n")
    op2 = Op.new(op: :add, path: spec_81, added_content: "content\n")

    out = StringIO.new
    err = StringIO.new
    code = CodexEditGates.dispatch(ops: [op1, op2], payload: payload, out: out, err: err)

    assert_equal 2, code, "the first op's code-gate violation must still deny the whole call"
    ledger = File.read(File.join(intent_dir_81, "savepoint.md"))
    assert_includes ledger, "Why  started",
      "the second op's savepoint ledger line must land even though the first op denied"
  end

  def test_first_deny_wins_and_stops_evaluation
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n")

    project_file = File.join(@root, "code", "bad.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    silence_stderr do
      Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo")
    end

    malformed_path = File.join(@store, "1--demo", "1--demo.md")
    op1 = Op.new(op: :update, path: project_file, added_content: "puts 2\n")
    op2 = Op.new(op: :add, path: malformed_path, added_content: malformed_intent_content)

    out = StringIO.new
    err = StringIO.new
    code = CodexEditGates.dispatch(ops: [op1, op2], payload: payload, out: out, err: err)

    assert_equal 2, code
    assert_includes err.string, "PLASTIC GATE"
    refute_includes err.string, "PLASTIC CREATE GATE",
      "the first op's code-gate deny must stop evaluation before the second op's create-gate ever runs"
  end

  def test_lock_gate_deny_is_json_on_stdout_at_exit_zero
    intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"), "## Active\n- [96 - demo](96--demo/96--demo.md)\n\n## Future\n")

    plan = File.join(intent_dir, "plan.md")
    op = Op.new(op: :update, path: plan, added_content: "content\n")

    out = StringIO.new
    err = StringIO.new
    code = CodexEditGates.dispatch(ops: [op], payload: payload, out: out, err: err)

    assert_equal 0, code, "lock-gate must never exit non-zero"
    assert_includes out.string, '"permissionDecision":"deny"'
  end

  def test_a_second_op_cannot_emit_a_second_deny_json
    intent_dir_a = File.join(@store, "96--demo")
    FileUtils.mkdir_p(intent_dir_a)
    File.write(File.join(intent_dir_a, "96--demo.md"), "## Intent\nDemo\n")
    intent_dir_b = File.join(@store, "97--demo")
    FileUtils.mkdir_p(intent_dir_b)
    File.write(File.join(intent_dir_b, "97--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"),
      "## Active\n- [96 - demo](96--demo/96--demo.md)\n- [97 - demo](97--demo/97--demo.md)\n\n## Future\n")

    plan_a = File.join(intent_dir_a, "plan.md")
    plan_b = File.join(intent_dir_b, "plan.md")
    op1 = Op.new(op: :update, path: plan_a, added_content: "content\n")
    op2 = Op.new(op: :update, path: plan_b, added_content: "content\n")

    out = StringIO.new
    err = StringIO.new
    code = CodexEditGates.dispatch(ops: [op1, op2], payload: payload, out: out, err: err)

    assert_equal 0, code
    parsed = JSON.parse(out.string) # raises on trailing data if a second JSON object were appended
    assert_kind_of Hash, parsed
    assert_equal "deny", parsed.dig("hookSpecificOutput", "permissionDecision")
  end

  # ---- crash isolation ----

  def test_a_raising_gate_is_isolated_and_the_others_still_run
    malformed_path = File.join(@store, "1--demo", "1--demo.md")
    op = Op.new(op: :add, path: malformed_path, added_content: malformed_intent_content)
    ctx = CodexEditGates.context_for(payload, op)

    route = lambda do |gate, c|
      raise "boom" if gate == "lock-gate"
      CodexEditGates.route_for(op).call(gate, c)
    end

    out = StringIO.new
    err = StringIO.new
    code = EditGates.dispatch(ctx: ctx, route: route, gate_tools: CodexEditGates::DENY_TOOLS, out: out, err: err)

    assert_equal 2, code, "create-gate, the later gate, must still deny despite lock-gate raising"
    assert_equal 1, err.string.lines.count { |l| l.include?("plastic lock-gate error:") }
    assert_includes err.string, "PLASTIC CREATE GATE"
  end

  # ---- no subprocess on the edit path ----

  def test_the_codex_edit_path_spawns_no_subprocess
    source = File.read(File.expand_path("../scripts/lib/codex_edit_gates.rb", __dir__))
    refute_match(/IO\.popen|Open3|system\(|spawn\(|`|%x/, source,
      "intent 251: a spawn site here reintroduces the eight-process cost this intent removed")
  end
end
