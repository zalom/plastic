# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "stringio"
require_relative "../scripts/lib/edit_gates"

# ACTION_5 (intent 244), chain link 3 of spec D-n's correctness argument. The
# dispatcher's genuinely NEW behavior, none of it exercised by the 45 untouched
# contract tests or by ACTION_4's differential equivalence test: fixed order
# plus first-deny-wins, crash isolation, the # plastic-ok escape's scope,
# savepoint-pre's unconditional append, and tool_name applicability.
#
# Every new test here comes with a named way to make it go red (intent 208: a
# check that cannot fail is not a check; intent 203: a gate needs a must-deny
# test or its tests are decoration).
class EditGatesDispatcherTest < Minitest::Test
  DISPATCHER = File.expand_path("../scripts/hook-edit-gates", __dir__)
  EDIT_GATES_LIB = File.expand_path("../scripts/lib/edit_gates.rb", __dir__)
  HOOK_REGISTRY_LIB = File.expand_path("../scripts/lib/hook_registry.rb", __dir__)
  NEW_INTENT = File.expand_path("../scripts/new-intent", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)

  def setup
    @tmpdirs = []
    @safe_tmp = mktmp("compose-safe-tmp")
    @safe_home = mktmp("compose-safe-home")
  end

  def teardown
    @tmpdirs.each { |d| FileUtils.rm_rf(d) }
  end

  def mktmp(name)
    d = Dir.mktmpdir(name)
    @tmpdirs << d
    d
  end

  def base_env
    { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @safe_tmp, "PLASTIC_HOME" => nil, "HOME" => @safe_home }
  end

  def run_dispatcher(payload, env: {})
    Open3.capture3(base_env.merge(env), RbConfig.ruby, DISPATCHER, stdin_data: JSON.generate(payload))
  end

  def scaffold_intent(store, intent:, slug:)
    out = IO.popen([RbConfig.ruby, NEW_INTENT, "--templates", TEMPLATES, "--store", store,
                    "--intent", intent, "--slug", slug], err: [:child, :out], &:read)
    intent_dir = out.strip
    raise "new-intent failed: #{out}" unless $?.success?
    intent_dir
  end

  # `load` re-defining EditGates::Deny (a Struct constant) prints an "already
  # initialized constant" warning each time; silence it, it is test-internal
  # reload noise, not signal.
  def quiet_load(path)
    saved = $VERBOSE
    $VERBOSE = nil
    load path
  ensure
    $VERBOSE = saved
  end

  # =====================================================================
  # Test 1: a crash inside one gate does not stop the others, does not deny (AC9)
  # =====================================================================

  # 1a, in-process, via the injected route: EditGates.dispatch takes route: as
  # a parameter, so this needs no eval, no ENV seam, no global config.
  def test_a_crashing_gate_does_not_stop_the_others_and_does_not_deny
    seen = []
    route = lambda do |gate, _ctx|
      seen << gate
      raise "boom" if gate == "code-gate"
      nil
    end
    err = StringIO.new
    out = StringIO.new
    ctx = EditGates::Context.new(tool_name: "Write", file_path: "/tmp/x.md", gate_path: "/tmp/x.md")

    code = EditGates.dispatch(ctx: ctx, route: route, out: out, err: err)

    assert_equal 0, code, "a gate crash must never deny"
    assert_equal HookRegistry::GATE_TOOLS.keys, seen, "all five gates must still be visited"
    assert_equal 1, err.string.lines.length, "exactly one error line"
    assert_equal "plastic code-gate error: boom\n", err.string
    assert_equal "", out.string
  end

  # The other half of D-i: a crash must not silence a LATER sibling's genuine deny.
  def test_a_crashing_gate_does_not_silence_a_later_denying_sibling
    route = lambda do |gate, _ctx|
      raise "boom" if gate == "code-gate"
      next EditGates::Deny.new(shape: :stderr, lines: ["denied by links-gate"]) if gate == "links-gate"
      nil
    end
    err = StringIO.new
    out = StringIO.new
    ctx = EditGates::Context.new(tool_name: "Write", file_path: "/tmp/x.md", gate_path: "/tmp/x.md")

    code = EditGates.dispatch(ctx: ctx, route: route, out: out, err: err)

    assert_equal 2, code, "the later sibling's genuine deny must still fire"
    assert_includes err.string, "plastic code-gate error: boom"
    assert_includes err.string, "denied by links-gate"
  end

  # 1b, end to end, through the real launcher: force a REAL exception with a
  # fixture (an unreadable UNRELATED store dir), not a stub, mirroring
  # test/links_gate_hook_test.rb:102-124. The crash-triggering payload must
  # target the subject intent's OWN file (the only way to reach links-gate's
  # store-scan code path at all), which means code-gate structurally cannot be
  # the sibling that still denies here: it exempts any path inside the
  # intent's own dir. create-gate, the gate immediately AFTER links-gate in
  # fixed order, is the sibling that proves the crash did not swallow it.
  def test_crash_isolation_end_to_end_through_the_real_launcher
    skip "chmod 0000 does not block root; cannot exercise the permission failure" if Process.uid.zero?

    home = mktmp("compose-crash-home")
    store = File.join(home, "store")
    FileUtils.mkdir_p(store)
    File.write(File.join(home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n\n## Completed\n")

    intent_dir = scaffold_intent(store, intent: "CrashSubject", slug: "crashsubject")
    intent_file = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    born_complete = File.read(intent_file)

    # Tamper the Links section (triggers links-gate's store-wide scan) AND
    # remove chain: (breaks create-gate's validation), so the sibling right
    # after links-gate still has something to deny once links-gate crashes.
    bad = born_complete
      .sub("<!-- No sources or chain; this intent has no graph edges to project. -->\n",
           "- [[99--nowhere|Nowhere]]\n")
      .sub(/^chain:.*\n/, "")

    broken_store = File.join(home, "projects", "broken", "store")
    FileUtils.mkdir_p(broken_store)
    File.chmod(0o000, broken_store)

    begin
      env = { "PLASTIC_HOME" => home, "HOME" => mktmp("compose-crash-fakehome"),
              "PLASTIC_TMP" => mktmp("compose-crash-tmp") }
      out, err, status = run_dispatcher(
        { "tool_name" => "Write", "tool_input" => { "file_path" => intent_file, "content" => bad } },
        env: env,
      )

      # Fail-open means the CRASHING gate itself never denies (its exception
      # never impersonates a deny); it does NOT mean the overall call always
      # allows. create-gate, the sibling right after links-gate, still has a
      # genuine deny of its own here (missing chain:), and that deny must
      # still propagate as the overall exit code, proving the crash did not
      # swallow it.
      assert_equal 2, status.exitstatus,
                   "create-gate's own deny must still propagate past the links-gate crash: #{out} / #{err}"
      error_lines = err.lines.select { |l| l.include?("plastic links-gate error:") }
      assert_equal 1, error_lines.length, "exactly one links-gate crash line: #{err.inspect}"
      assert_includes err, "PLASTIC CREATE GATE",
                       "create-gate, the sibling right after links-gate, must still run and deny: #{err.inspect}"
    ensure
      File.chmod(0o700, broken_store) if Dir.exist?(broken_store)
    end
  end

  # Red-phase proof for test 1: re-raising instead of continuing must break
  # test 1a; stopping (return 0) instead of continuing must break the sibling
  # half. Both mutate scripts/lib/edit_gates.rb's dispatch method, assert the
  # expected failure directly (without needing to re-invoke Minitest
  # internals), then restore.
  # This test's assertions run IN-PROCESS against EditGates.dispatch (already
  # require_relative'd at file load), so a plain File.write of the mutated
  # source is NOT enough: Ruby does not hot-reload a require. Each mutation is
  # followed by `load EDIT_GATES_LIB` to force Ruby to re-execute the file and
  # redefine EditGates.dispatch in place, and the restore path does the same,
  # so no mutation ever bleeds into a later test in this same suite process.
  def test_red_phase_proof_dispatch_isolation_is_load_bearing
    original = File.read(EDIT_GATES_LIB)

    reraise = original.sub(
      "rescue StandardError => e\n          err.puts \"plastic \#{gate} error: \#{e.message}\"\n          next",
      "rescue StandardError => e\n          raise e",
    )
    refute_equal original, reraise, "sanity: the re-raise mutation must actually change the file"
    File.write(EDIT_GATES_LIB, reraise)
    quiet_load(EDIT_GATES_LIB)
    begin
      route = lambda { |gate, _ctx| raise "boom" if gate == "code-gate" }
      ctx = EditGates::Context.new(tool_name: "Write", file_path: "/tmp/x.md", gate_path: "/tmp/x.md")
      escaped = assert_raises(StandardError) do
        EditGates.dispatch(ctx: ctx, route: route, out: StringIO.new, err: StringIO.new)
      end
      assert_equal "boom", escaped.message, "with the rescue removed, the exception must escape dispatch"
    ensure
      File.write(EDIT_GATES_LIB, original)
      quiet_load(EDIT_GATES_LIB)
    end

    stop_early = original.sub(
      "          err.puts \"plastic \#{gate} error: \#{e.message}\"\n          next",
      "          err.puts \"plastic \#{gate} error: \#{e.message}\"\n          return 0",
    )
    refute_equal original, stop_early, "sanity: the stop-early mutation must actually change the file"
    File.write(EDIT_GATES_LIB, stop_early)
    quiet_load(EDIT_GATES_LIB)
    begin
      route = lambda do |gate, _ctx|
        raise "boom" if gate == "code-gate"
        next EditGates::Deny.new(shape: :stderr, lines: ["denied by links-gate"]) if gate == "links-gate"
        nil
      end
      ctx = EditGates::Context.new(tool_name: "Write", file_path: "/tmp/x.md", gate_path: "/tmp/x.md")
      code = EditGates.dispatch(ctx: ctx, route: route, out: StringIO.new, err: StringIO.new)
      refute_equal 2, code, "with next replaced by return 0, the sibling's later deny must be swallowed"
    ensure
      File.write(EDIT_GATES_LIB, original)
      quiet_load(EDIT_GATES_LIB)
    end
  end

  # =====================================================================
  # Test 2: # plastic-ok skips only code-gate (AC10)
  # =====================================================================

  def test_plastic_ok_escape_does_not_bypass_lock_gate
    root = mktmp("compose-escape-lock")
    store = File.join(root, "store")
    intent_dir = File.join(store, "70--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "70--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(root, "INDEX.md"), "## Active\n- [70 — demo](70--demo/70--demo.md)\n\n## Future\n")
    plan_path = File.join(intent_dir, "plan.md")
    home = mktmp("compose-escape-lock-home")

    log = File.join(home, ".plastic", ".cache", "gate-escapes.log")
    env = { "PLASTIC_TMP" => mktmp("compose-escape-lock-tmp"), "HOME" => home }
    out, err, status = run_dispatcher(
      { "tool_name" => "Write", "tool_input" => { "file_path" => plan_path, "content" => "x\n# plastic-ok\n" } },
      env: env,
    )

    assert_equal 0, status.exitstatus
    parsed = (JSON.parse(out) rescue nil)
    assert parsed, "stdout must be lock-gate's deny JSON, the escape must not bypass it: #{out.inspect}"
    assert_equal "deny", parsed.dig("hookSpecificOutput", "permissionDecision")
    assert_equal "", err
    refute File.exist?(log),
           "the escape audit line must NOT be written when lock-gate denies first (spec D-c: " \
           "evaluation stops at lock-gate, code-gate never runs, so it never logs)"
  end

  def test_plastic_ok_escape_does_not_bypass_create_gate
    home = mktmp("compose-escape-create-home")
    store = File.join(home, "store")
    FileUtils.mkdir_p(store)
    intent_dir = scaffold_intent(store, intent: "EscapeCreate", slug: "escapecreate")
    intent_file = File.join(intent_dir, "#{File.basename(intent_dir)}.md")

    # An Edit whose new_string alone ends with the escape marker (satisfying
    # code-gate's own check) while replacing the chain: frontmatter line, so
    # create-gate's simulated result is invalid; the ## Links section body is
    # untouched, so links-gate short-circuits allow ("no Links change") and
    # never becomes the gate that answers here.
    payload = { "tool_name" => "Edit",
                "tool_input" => { "file_path" => intent_file,
                                   "old_string" => "chain: []\n", "new_string" => "# plastic-ok\n" } }
    env = { "PLASTIC_TMP" => mktmp("compose-escape-create-tmp"), "HOME" => mktmp("compose-escape-create-fakehome") }
    out, err, status = run_dispatcher(payload, env: env)

    assert_equal 2, status.exitstatus
    assert_includes err, "PLASTIC CREATE GATE", "the escape must not bypass create-gate: #{err.inspect}"
    assert_equal "", out
  end

  # Red-phase proof for test 2: hoisting the PLASTIC_OK_RE check out of
  # code_gate into dispatch (so it short-circuits every gate) must turn both
  # cases above red.
  def test_red_phase_proof_escape_scope_is_load_bearing
    original = File.read(EDIT_GATES_LIB)
    mutated = original.sub(
      "  def dispatch(ctx:, route:, gate_tools: HookRegistry::GATE_TOOLS, out: $stdout, err: $stderr)\n" \
      "    gate_tools.each do |gate, tools|",
      "  def dispatch(ctx:, route:, gate_tools: HookRegistry::GATE_TOOLS, out: $stdout, err: $stderr)\n" \
      "    new_content = ctx.content || ctx.new_string || \"\"\n" \
      "    return 0 if new_content && Bridge::PLASTIC_OK_RE.match?(new_content.chomp)\n\n" \
      "    gate_tools.each do |gate, tools|",
    )
    refute_equal original, mutated, "sanity: the mutation must actually hoist the escape check"
    File.write(EDIT_GATES_LIB, mutated)
    begin
      root = mktmp("compose-escape-redphase")
      store = File.join(root, "store")
      intent_dir = File.join(store, "73--demo")
      FileUtils.mkdir_p(intent_dir)
      File.write(File.join(intent_dir, "73--demo.md"), "## Intent\nDemo\n")
      File.write(File.join(root, "INDEX.md"), "## Active\n- [73 — demo](73--demo/73--demo.md)\n\n## Future\n")
      plan_path = File.join(intent_dir, "plan.md")
      env = { "PLASTIC_TMP" => mktmp("compose-escape-redphase-tmp"), "HOME" => mktmp("compose-escape-redphase-home") }
      out, _err, status = run_dispatcher(
        { "tool_name" => "Write", "tool_input" => { "file_path" => plan_path, "content" => "x\n# plastic-ok\n" } },
        env: env,
      )
      # With the check hoisted, lock-gate's deny is bypassed entirely: exit 0
      # with EMPTY stdout (no deny JSON), where the true code emits the deny.
      assert_equal 0, status.exitstatus
      refute_includes out, "permissionDecision",
                       "with the escape hoisted above the loop, lock-gate's deny must be bypassed; " \
                       "this is the RED signal the true code must never produce"
    ensure
      File.write(EDIT_GATES_LIB, original)
    end
  end

  # =====================================================================
  # Test 3: savepoint-pre's ledger append fires on a call another gate denies (AC8)
  # =====================================================================

  def test_savepoint_pre_ledger_appends_on_a_call_lock_gate_denies
    root = mktmp("compose-savepoint-deny")
    store = File.join(root, "store")
    intent_dir = File.join(store, "71--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "71--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(root, "INDEX.md"), "## Active\n- [71 — demo](71--demo/71--demo.md)\n\n## Future\n")
    spec_path = File.join(intent_dir, "spec.md")

    env = { "PLASTIC_TMP" => mktmp("compose-savepoint-deny-tmp"), "HOME" => mktmp("compose-savepoint-deny-home") }
    out, err, status = run_dispatcher(
      { "tool_name" => "Write", "tool_input" => { "file_path" => spec_path } }, env: env,
    )

    assert_equal 0, status.exitstatus
    parsed = (JSON.parse(out) rescue nil)
    assert parsed, "stdout must be lock-gate's deny JSON: #{out.inspect} / #{err.inspect}"
    assert_equal "deny", parsed.dig("hookSpecificOutput", "permissionDecision")

    ledger = File.join(intent_dir, "savepoint.md")
    assert File.exist?(ledger), "the started ledger line must land even though lock-gate denied the call"
    assert_includes File.read(ledger), "Why  started"
  end

  # Red-phase proof for test 3: reordering GATE_TOOLS so savepoint-pre runs
  # LAST must turn the case above red (lock-gate's deny ends evaluation before
  # the append ever happens). This also demonstrates the key order itself is
  # load-bearing, not incidental.
  def test_red_phase_proof_savepoint_first_ordering_is_load_bearing
    original = File.read(HOOK_REGISTRY_LIB)
    mutated = original.sub(
      "  GATE_TOOLS = {\n" \
      "    \"savepoint-pre\" => %w[Write Edit].freeze,\n" \
      "    \"lock-gate\"     => (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).freeze,\n" \
      "    \"code-gate\"     => (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).freeze,\n" \
      "    \"links-gate\"    => %w[Write Edit].freeze,\n" \
      "    \"create-gate\"   => (%w[Write Edit] + SERENA_EDIT_TOOLS).freeze,\n" \
      "  }.freeze",
      "  GATE_TOOLS = {\n" \
      "    \"lock-gate\"     => (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).freeze,\n" \
      "    \"code-gate\"     => (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).freeze,\n" \
      "    \"links-gate\"    => %w[Write Edit].freeze,\n" \
      "    \"create-gate\"   => (%w[Write Edit] + SERENA_EDIT_TOOLS).freeze,\n" \
      "    \"savepoint-pre\" => %w[Write Edit].freeze,\n" \
      "  }.freeze",
    )
    refute_equal original, mutated, "sanity: the mutation must actually reorder the table"
    File.write(HOOK_REGISTRY_LIB, mutated)
    begin
      root = mktmp("compose-savepoint-redphase")
      store = File.join(root, "store")
      intent_dir = File.join(store, "72--demo")
      FileUtils.mkdir_p(intent_dir)
      File.write(File.join(intent_dir, "72--demo.md"), "## Intent\nDemo\n")
      File.write(File.join(root, "INDEX.md"), "## Active\n- [72 — demo](72--demo/72--demo.md)\n\n## Future\n")
      spec_path = File.join(intent_dir, "spec.md")
      env = { "PLASTIC_TMP" => mktmp("compose-savepoint-redphase-tmp"),
              "HOME" => mktmp("compose-savepoint-redphase-home") }
      run_dispatcher({ "tool_name" => "Write", "tool_input" => { "file_path" => spec_path } }, env: env)

      ledger = File.join(intent_dir, "savepoint.md")
      refute File.exist?(ledger),
             "with savepoint-pre reordered LAST, lock-gate's deny must end evaluation before the " \
             "append ever happens; this must go RED against the true (savepoint-pre-first) table"
    ensure
      File.write(HOOK_REGISTRY_LIB, original)
    end
  end

  # =====================================================================
  # Test 4: applicability by tool_name (AC7 dispatcher half, H4)
  # =====================================================================

  # Runs a genuinely FRESH Ruby process each time (never the already-loaded,
  # frozen GATE_TOOLS in THIS test process), so the red-phase proof's registry
  # mutation is observed correctly.
  def run_fresh_applicability_check(tool_name)
    script = <<~RUBY
      require_relative #{EDIT_GATES_LIB.inspect}
      require "stringio"
      seen = []
      route = lambda { |gate, _ctx| seen << gate; nil }
      ctx = EditGates::Context.new(tool_name: #{tool_name.inspect}, file_path: "/tmp/x.md", gate_path: "/tmp/x.md")
      code = EditGates.dispatch(ctx: ctx, route: route, out: StringIO.new, err: StringIO.new)
      puts "\#{code}|\#{seen.join(',')}"
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", script)
    raise "applicability probe failed: #{err}" unless status.success?
    code_str, gates_str = out.strip.split("|", 2)
    [code_str.to_i, (gates_str || "").split(",")]
  end

  def test_applicability_table_by_tool_name
    full = %w[savepoint-pre lock-gate code-gate links-gate create-gate]
    cases = {
      "Write" => full,
      "Edit" => full,
      "NotebookEdit" => %w[lock-gate code-gate],
      "mcp__serena__replace_content" => %w[lock-gate code-gate create-gate],
      "Bash" => [],
      nil => [],
      "SomethingUnknown" => [],
    }

    cases.each do |tool_name, expected|
      code, seen = run_fresh_applicability_check(tool_name)
      assert_equal 0, code, "tool_name=#{tool_name.inspect} must always allow when no route denies"
      assert_equal expected, seen, "tool_name=#{tool_name.inspect}"
    end
  end

  # Red-phase proof for test 4: widening create-gate's table entry to include
  # NotebookEdit must turn the NotebookEdit row red (the same falsification
  # ACTION_6's registry-side pinning test provides, from the dispatcher side).
  def test_red_phase_proof_widening_create_gate_coverage_turns_notebookedit_row_red
    original = File.read(HOOK_REGISTRY_LIB)
    mutated = original.sub(
      '"create-gate"   => (%w[Write Edit] + SERENA_EDIT_TOOLS).freeze,',
      '"create-gate"   => (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).freeze,',
    )
    refute_equal original, mutated, "sanity: the mutation must actually widen create-gate's coverage"
    File.write(HOOK_REGISTRY_LIB, mutated)
    begin
      _code, seen = run_fresh_applicability_check("NotebookEdit")
      refute_equal %w[lock-gate code-gate], seen,
                   "widening create-gate's coverage to NotebookEdit must turn this row RED"
    ensure
      File.write(HOOK_REGISTRY_LIB, original)
    end
  end
end
