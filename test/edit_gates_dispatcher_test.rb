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

  def run_dispatcher(payload, env: {}, dispatcher: DISPATCHER)
    Open3.capture3(base_env.merge(env), RbConfig.ruby, dispatcher, stdin_data: JSON.generate(payload))
  end

  # Fix 5 (post-review, intent 244): red-phase proofs mutate a COPY of the
  # shipped scripts/ tree under a tmpdir, never the real
  # scripts/lib/edit_gates.rb, scripts/lib/hook_registry.rb or
  # scripts/hook-edit-gates in the working tree. An interrupt mid-proof must
  # never leave a shipped file corrupted, and parallel test runs must never
  # race on the same file. `overrides` maps a path relative to the repo's
  # scripts/ directory (e.g. "lib/edit_gates.rb") to its mutated content;
  # every other file under scripts/ is copied verbatim so require_relative
  # keeps resolving inside the copy exactly like the real tree, and a
  # dispatcher copy can be run standalone or an in-process lib copy can be
  # `load`ed with its sibling deps present.
  def mutated_scripts_dir(overrides)
    real_scripts = File.expand_path("../scripts", __dir__)
    copy = File.join(mktmp("mutated-scripts"), "scripts")
    FileUtils.cp_r(real_scripts, copy)
    overrides.each { |relative, content| File.write(File.join(copy, relative), content) }
    copy
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

    code = EditGates.dispatch(ctx: ctx, route: route, out: out, err: err,
                              block_log: File.join(@safe_tmp, "block.log"))

    assert_equal 2, code, "the later sibling's genuine deny must still fire"
    assert_includes err.string, "plastic code-gate error: boom"
    assert_includes err.string, "denied by links-gate"
  end

  # Fix 7 (post-review, intent 244): outcome.shape / out.print / err.puts must
  # live INSIDE the same rescue as route.call, so a MALFORMED outcome (not a
  # raised exception, a genuinely bad return value) is isolated exactly like
  # a crashing gate and never aborts the gates still to come. A route that
  # returns a plain String (no #shape method) reproduces this without an
  # artificial exception.
  def test_a_malformed_outcome_does_not_stop_the_others_and_does_not_deny
    seen = []
    route = lambda do |gate, _ctx|
      seen << gate
      next "not-a-deny-object" if gate == "code-gate"
      nil
    end
    err = StringIO.new
    out = StringIO.new
    ctx = EditGates::Context.new(tool_name: "Write", file_path: "/tmp/x.md", gate_path: "/tmp/x.md")

    code = EditGates.dispatch(ctx: ctx, route: route, out: out, err: err,
                              block_log: File.join(@safe_tmp, "block.log"))

    assert_equal 0, code, "a malformed outcome must never deny"
    assert_equal HookRegistry::GATE_TOOLS.keys, seen, "all five gates must still be visited"
    assert_equal 1, err.string.lines.length, "exactly one error line"
    assert_includes err.string, "plastic code-gate error:"
    assert_equal "", out.string
  end

  # The other half: a malformed outcome must not silence a LATER sibling's genuine deny.
  def test_a_malformed_outcome_does_not_silence_a_later_denying_sibling
    route = lambda do |gate, _ctx|
      next "not-a-deny-object" if gate == "code-gate"
      next EditGates::Deny.new(shape: :stderr, lines: ["denied by links-gate"]) if gate == "links-gate"
      nil
    end
    err = StringIO.new
    out = StringIO.new
    ctx = EditGates::Context.new(tool_name: "Write", file_path: "/tmp/x.md", gate_path: "/tmp/x.md")

    code = EditGates.dispatch(ctx: ctx, route: route, out: out, err: err,
                              block_log: File.join(@safe_tmp, "block.log"))

    assert_equal 2, code, "the later sibling's genuine deny must still fire"
    assert_includes err.string, "plastic code-gate error:"
    assert_includes err.string, "denied by links-gate"
  end

  # Red-phase proof for fix 7: narrow the rescue back to wrap ONLY route.call
  # (the pre-fix shape, outcome.shape/out.print/err.puts left OUTSIDE it) and
  # confirm the malformed-outcome test above goes red: the NoMethodError from
  # `outcome.shape` on a plain String escapes dispatch entirely instead of
  # being isolated per-gate, so the LATER sibling never gets a chance to run.
  def test_red_phase_proof_fix7_rescue_scope_is_load_bearing
    original = File.read(EDIT_GATES_LIB)
    narrowed = original.sub(
      "      begin\n" \
      "        outcome = route.call(gate, ctx)\n" \
      "        next unless outcome\n" \
      "\n" \
      "        # intent 229: one block-log line per deny, both shapes, one call site.\n" \
      "        # Every helper here rescues internally, so nothing new can reach this\n" \
      "        # method's rescue and turn a logging problem into a changed decision.\n" \
      "        subject = ctx.gate_path.to_s.empty? ? ctx.file_path.to_s : ctx.gate_path.to_s\n" \
      "        log_block(gate: gate, session: ctx.session, intent: block_intent_id(subject),\n" \
      "                  subject: subject, rule: deny_reason(outcome), path: block_log)\n" \
      "\n" \
      "        if outcome.shape == :json\n" \
      "          out.print outcome.stdout\n" \
      "          return 0\n" \
      "        else\n" \
      "          outcome.lines.each { |line| err.puts line }\n" \
      "          return 2\n" \
      "        end\n" \
      "      rescue StandardError => e\n" \
      "        # Fix 7: outcome.shape / out.print / err.puts now live INSIDE the same\n" \
      "        # rescue as route.call, so a malformed outcome or a stream write\n" \
      "        # failure (e.g. EPIPE) is isolated exactly like a raising gate, and\n" \
      "        # never aborts the gates still to come.\n" \
      "        err.puts \"plastic \#{gate} error: \#{e.message}\"\n" \
      "        next\n" \
      "      end",
      "      outcome =\n" \
      "        begin\n" \
      "          route.call(gate, ctx)\n" \
      "        rescue StandardError => e\n" \
      "          err.puts \"plastic \#{gate} error: \#{e.message}\"\n" \
      "          next\n" \
      "        end\n" \
      "\n" \
      "      next unless outcome\n" \
      "\n" \
      "      subject = ctx.gate_path.to_s.empty? ? ctx.file_path.to_s : ctx.gate_path.to_s\n" \
      "      log_block(gate: gate, session: ctx.session, intent: block_intent_id(subject),\n" \
      "                subject: subject, rule: deny_reason(outcome), path: block_log)\n" \
      "\n" \
      "      if outcome.shape == :json\n" \
      "        out.print outcome.stdout\n" \
      "        return 0\n" \
      "      else\n" \
      "        outcome.lines.each { |line| err.puts line }\n" \
      "        return 2\n" \
      "      end",
    )
    refute_equal original, narrowed, "sanity: the mutation must actually narrow the rescue scope"
    copy_dir = mutated_scripts_dir("lib/edit_gates.rb" => narrowed)
    quiet_load(File.join(copy_dir, "lib", "edit_gates.rb"))
    begin
      route = lambda do |gate, _ctx|
        next "not-a-deny-object" if gate == "code-gate"
        next EditGates::Deny.new(shape: :stderr, lines: ["denied by links-gate"]) if gate == "links-gate"
        nil
      end
      ctx = EditGates::Context.new(tool_name: "Write", file_path: "/tmp/x.md", gate_path: "/tmp/x.md")
      escaped = assert_raises(NoMethodError) do
        EditGates.dispatch(ctx: ctx, route: route, out: StringIO.new, err: StringIO.new,
                            block_log: File.join(@safe_tmp, "block.log"))
      end
      assert_match(/shape/, escaped.message,
                   "with the rescue narrowed to route.call only, outcome.shape's NoMethodError " \
                   "must escape dispatch instead of being isolated; this is the RED signal")
    ensure
      quiet_load(EDIT_GATES_LIB)
    end
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
      "      rescue StandardError => e\n" \
      "        # Fix 7: outcome.shape / out.print / err.puts now live INSIDE the same\n" \
      "        # rescue as route.call, so a malformed outcome or a stream write\n" \
      "        # failure (e.g. EPIPE) is isolated exactly like a raising gate, and\n" \
      "        # never aborts the gates still to come.\n" \
      "        err.puts \"plastic \#{gate} error: \#{e.message}\"\n" \
      "        next\n" \
      "      end",
      "      rescue StandardError => e\n" \
      "        raise e\n" \
      "      end",
    )
    refute_equal original, reraise, "sanity: the re-raise mutation must actually change the file"
    copy_dir = mutated_scripts_dir("lib/edit_gates.rb" => reraise)
    quiet_load(File.join(copy_dir, "lib", "edit_gates.rb"))
    begin
      route = lambda { |gate, _ctx| raise "boom" if gate == "code-gate" }
      ctx = EditGates::Context.new(tool_name: "Write", file_path: "/tmp/x.md", gate_path: "/tmp/x.md")
      escaped = assert_raises(StandardError) do
        EditGates.dispatch(ctx: ctx, route: route, out: StringIO.new, err: StringIO.new)
      end
      assert_equal "boom", escaped.message, "with the rescue removed, the exception must escape dispatch"
    ensure
      quiet_load(EDIT_GATES_LIB)
    end

    stop_early = original.sub(
      "        err.puts \"plastic \#{gate} error: \#{e.message}\"\n        next\n      end",
      "        err.puts \"plastic \#{gate} error: \#{e.message}\"\n        return 0\n      end",
    )
    refute_equal original, stop_early, "sanity: the stop-early mutation must actually change the file"
    copy_dir = mutated_scripts_dir("lib/edit_gates.rb" => stop_early)
    quiet_load(File.join(copy_dir, "lib", "edit_gates.rb"))
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
      "  def dispatch(ctx:, route:, gate_tools: HookRegistry::GATE_TOOLS, out: $stdout, err: $stderr,\n" \
      "               block_log: nil)\n" \
      "    gate_tools.each do |gate, tools|",
      "  def dispatch(ctx:, route:, gate_tools: HookRegistry::GATE_TOOLS, out: $stdout, err: $stderr,\n" \
      "               block_log: nil)\n" \
      "    new_content = ctx.content || ctx.new_string || \"\"\n" \
      "    return 0 if new_content && Bridge::PLASTIC_OK_RE.match?(new_content.chomp)\n\n" \
      "    gate_tools.each do |gate, tools|",
    )
    refute_equal original, mutated, "sanity: the mutation must actually hoist the escape check"
    copy_dir = mutated_scripts_dir("lib/edit_gates.rb" => mutated)
    dispatcher_copy = File.join(copy_dir, "hook-edit-gates")
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
      env: env, dispatcher: dispatcher_copy,
    )
    # With the check hoisted, lock-gate's deny is bypassed entirely: exit 0
    # with EMPTY stdout (no deny JSON), where the true code emits the deny.
    assert_equal 0, status.exitstatus
    refute_includes out, "permissionDecision",
                     "with the escape hoisted above the loop, lock-gate's deny must be bypassed; " \
                     "this is the RED signal the true code must never produce"
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
    copy_dir = mutated_scripts_dir("lib/hook_registry.rb" => mutated)
    dispatcher_copy = File.join(copy_dir, "hook-edit-gates")
    root = mktmp("compose-savepoint-redphase")
    store = File.join(root, "store")
    intent_dir = File.join(store, "72--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "72--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(root, "INDEX.md"), "## Active\n- [72 — demo](72--demo/72--demo.md)\n\n## Future\n")
    spec_path = File.join(intent_dir, "spec.md")
    env = { "PLASTIC_TMP" => mktmp("compose-savepoint-redphase-tmp"),
            "HOME" => mktmp("compose-savepoint-redphase-home") }
    run_dispatcher({ "tool_name" => "Write", "tool_input" => { "file_path" => spec_path } },
                   env: env, dispatcher: dispatcher_copy)

    ledger = File.join(intent_dir, "savepoint.md")
    refute File.exist?(ledger),
           "with savepoint-pre reordered LAST, lock-gate's deny must end evaluation before the " \
           "append ever happens; this must go RED against the true (savepoint-pre-first) table"
  end

  # Fix 3 (post-review, intent 244): savepoint-pre's own historical
  # precedence is INVERTED from links-gate/create-gate's ctx.file_path: old
  # hooks/savepoint-pre read tool_params.file_path FIRST, then
  # tool_input.file_path, while links-gate/create-gate read tool_input FIRST.
  # Pinned directly against EditGates.context_from, in-process, the most
  # direct falsification available (revert savepoint_path's `prefer:` and
  # this goes red immediately).
  def test_context_from_savepoint_path_prefers_tool_params_over_tool_input
    payload = { "tool_input" => { "file_path" => "/tmp/from-tool-input.md" },
                "tool_params" => { "file_path" => "/tmp/from-tool-params.md" } }
    ctx = EditGates.context_from(payload)
    assert_equal "/tmp/from-tool-params.md", ctx.savepoint_path,
                 "savepoint-pre's own historical precedence is tool_params FIRST, inverted from " \
                 "links-gate/create-gate's ctx.file_path"
    assert_equal "/tmp/from-tool-input.md", ctx.file_path,
                 "links-gate/create-gate's ctx.file_path stays tool_input FIRST"
  end

  # =====================================================================
  # Test 4: applicability by tool_name (AC7 dispatcher half, H4; regex
  # substring semantics + empty-tool_name-runs-everything, post-review
  # fixes 1 and 2)
  # =====================================================================

  # Runs a genuinely FRESH Ruby process each time (never the already-loaded,
  # frozen GATE_TOOLS in THIS test process), so a red-phase proof's mutation
  # is observed correctly. `edit_gates_lib` defaults to the real
  # scripts/lib/edit_gates.rb; red-phase proofs pass a mutated COPY's path
  # instead (fix 5: a proof must never write to the file in the working tree).
  def run_fresh_applicability_check(tool_name, edit_gates_lib: EDIT_GATES_LIB)
    script = <<~RUBY
      require_relative #{edit_gates_lib.inspect}
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
      # Fix 1: Claude's own matcher is an UNANCHORED REGEX ("Write|Edit"
      # matches "NotebookEdit" by substring on "Edit"), and every GATE_TOOLS
      # entry contains "Edit" somewhere, so NotebookEdit now visits all five
      # gates, exactly like the five old per-gate wrapper matcher groups did
      # before this intent collapsed them into one dispatcher (the coverage
      # narrowing an independent reviewer caught).
      "NotebookEdit" => full,
      "mcp__serena__replace_content" => %w[lock-gate code-gate create-gate],
      "Bash" => [],
      # Fix 2: a missing/empty tool_name means the harness matched but did
      # not name the tool (the five old wrappers never read tool_name at all,
      # so they ALL ran unconditionally on such a payload); it must run every
      # gate, not none (reverses this intent's own earlier H4 ruling).
      nil => full,
      "" => full,
      "SomethingUnknown" => [],
    }

    cases.each do |tool_name, expected|
      code, seen = run_fresh_applicability_check(tool_name)
      assert_equal 0, code, "tool_name=#{tool_name.inspect} must always allow when no route denies"
      assert_equal expected, seen, "tool_name=#{tool_name.inspect}"
    end
  end

  # Red-phase proof for fix 1: revert tool_applies? to plain string equality
  # (`tools.include?(tool_name)`, the pre-fix behavior) and confirm the
  # NotebookEdit row goes red: savepoint-pre/links-gate/create-gate stop
  # firing on it, reproducing the coverage-narrowing bug exactly.
  def test_red_phase_proof_regex_semantics_is_load_bearing
    original = File.read(EDIT_GATES_LIB)
    mutated = original.sub(
      "  def tool_applies?(tool_name, tools)\n" \
      "    return true if tool_name.to_s.empty?\n" \
      "    Regexp.new(tools.join(\"|\")).match?(tool_name.to_s)\n" \
      "  end",
      "  def tool_applies?(tool_name, tools)\n" \
      "    return true if tool_name.to_s.empty?\n" \
      "    tools.include?(tool_name.to_s)\n" \
      "  end",
    )
    refute_equal original, mutated, "sanity: the mutation must actually revert to string equality"
    copy_dir = mutated_scripts_dir("lib/edit_gates.rb" => mutated)
    _code, seen = run_fresh_applicability_check(
      "NotebookEdit", edit_gates_lib: File.join(copy_dir, "lib", "edit_gates.rb"),
    )
    refute_equal %w[savepoint-pre lock-gate code-gate links-gate create-gate], seen,
                 "string equality must under-match NotebookEdit; this row must go RED"
  end

  # Red-phase proof for fix 2: revert to skip-everything on an absent/empty
  # tool_name (this intent's earlier H4 behavior) and confirm the nil row
  # goes red: it must run zero gates instead of all five.
  def test_red_phase_proof_empty_tool_name_runs_everything_is_load_bearing
    original = File.read(EDIT_GATES_LIB)
    mutated = original.sub(
      "  def tool_applies?(tool_name, tools)\n" \
      "    return true if tool_name.to_s.empty?\n" \
      "    Regexp.new(tools.join(\"|\")).match?(tool_name.to_s)\n" \
      "  end",
      "  def tool_applies?(tool_name, tools)\n" \
      "    return false if tool_name.to_s.empty?\n" \
      "    Regexp.new(tools.join(\"|\")).match?(tool_name.to_s)\n" \
      "  end",
    )
    refute_equal original, mutated, "sanity: the mutation must actually revert to skip-everything"
    copy_dir = mutated_scripts_dir("lib/edit_gates.rb" => mutated)
    _code, seen = run_fresh_applicability_check(nil, edit_gates_lib: File.join(copy_dir, "lib", "edit_gates.rb"))
    refute_equal %w[savepoint-pre lock-gate code-gate links-gate create-gate], seen,
                 "skip-everything on an empty tool_name must under-match; this row must go RED"
  end

  # Red-phase proof for test 4 (H4-era coverage pin, retargeted): widening
  # create-gate's table entry to include a tool name it does not already
  # cover must turn that tool's row red. "Grep" replaces the original
  # "NotebookEdit" probe: under fix 1's regex substring semantics
  # NotebookEdit now legitimately matches every GATE_TOOLS entry (via "Edit"),
  # so it can no longer prove a coverage change; "Grep" shares no substring
  # with any current entry, so it still isolates a genuine widening.
  def test_red_phase_proof_widening_create_gate_coverage_turns_a_new_tool_row_red
    original = File.read(HOOK_REGISTRY_LIB)
    mutated = original.sub(
      '"create-gate"   => (%w[Write Edit] + SERENA_EDIT_TOOLS).freeze,',
      '"create-gate"   => (%w[Write Edit Grep] + SERENA_EDIT_TOOLS).freeze,',
    )
    refute_equal original, mutated, "sanity: the mutation must actually widen create-gate's coverage"
    copy_dir = mutated_scripts_dir("lib/hook_registry.rb" => mutated)
    _code, seen = run_fresh_applicability_check("Grep", edit_gates_lib: File.join(copy_dir, "lib", "edit_gates.rb"))
    refute_equal [], seen, "widening create-gate's coverage to Grep must turn this row RED"
  end

  # ACTION_8 cross-check: scripts/hook-edit-gates's `case gate` and
  # HookRegistry::GATE_TOOLS are also compared by EditGates.dispatch at
  # runtime (an unrouted gate returns nil and is treated as allow). Doctor's
  # claude_hooks_implemented_check pins this too, via a text extractor; this
  # is the plain in-process pin, independent of doctor's text-scan shape.
  def test_every_registered_gate_has_a_dispatcher_branch
    source = File.read(DISPATCHER)
    branches = source.scan(/^\s*when\s+"([^"]+)"/).flatten
    assert_equal HookRegistry::GATE_TOOLS.keys.sort, branches.sort
  end

  # Red-phase proof: delete one `when` arm and confirm the pin goes red.
  def test_red_phase_proof_deleting_a_dispatcher_branch_turns_the_cross_check_red
    original = File.read(DISPATCHER)
    mutated = original.sub(/^\s*when "create-gate".*\n/, "")
    refute_equal original, mutated, "sanity: the mutation must actually remove a when arm"
    branches = mutated.scan(/^\s*when\s+"([^"]+)"/).flatten
    refute_equal HookRegistry::GATE_TOOLS.keys.sort, branches.sort,
                 "deleting the create-gate arm must turn this pin RED"
  end

  # =====================================================================
  # intent 229: one block-log line per deny, six tab-separated fields
  # =====================================================================

  # intent 229 helpers -------------------------------------------------------
  def block_ctx(path)
    EditGates::Context.new(tool_name: "Write", file_path: path, gate_path: path, session: "sess-1")
  end

  def stderr_deny_route
    lambda do |gate, _ctx|
      next EditGates::Deny.new(shape: :stderr, lines: ["PLASTIC GATE  blocked by code-gate"]) if gate == "code-gate"
      nil
    end
  end

  def json_deny_route
    lambda do |gate, _ctx|
      next nil unless gate == "lock-gate"
      EditGates::Deny.new(shape: :json, stdout: JSON.generate(
        "hookSpecificOutput" => { "hookEventName" => "PreToolUse",
                                  "permissionDecision" => "deny",
                                  "permissionDecisionReason" => "intent 229 delivery lock is held" }
      ))
    end
  end

  def block_fields(log)
    lines = File.read(log).lines
    assert_equal 1, lines.size, "exactly one block line must be written"
    lines.first.chomp.split("\t", -1)
  end

  def test_dispatch_logs_six_fields_on_a_stderr_deny
    tmp = mktmp("block-log-stderr")
    store = File.join(tmp, "store", "229--demo")
    FileUtils.mkdir_p(store)
    path = File.join(store, "plan.md")
    log = File.join(tmp, "cache", "gate-blocks.log")

    code = EditGates.dispatch(ctx: block_ctx(path), route: stderr_deny_route,
                              out: StringIO.new, err: StringIO.new, block_log: log)

    assert_equal 2, code
    f = block_fields(log)
    assert_equal 6, f.size, "six tab-separated fields, always"
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, f[0], "field 1 is an ISO8601 UTC timestamp")
    assert_equal "code-gate", f[1], "field 2 is the gate that actually fired"
    assert_equal "sess-1", f[2]
    assert_equal "229", f[3], "field 4 is the intent id derived from the path"
    assert_equal path, f[4]
    assert_includes f[5], "blocked by code-gate"
  end

  def test_dispatch_logs_the_json_deny_reason
    tmp = mktmp("block-log-json")
    store = File.join(tmp, "store", "229--demo")
    FileUtils.mkdir_p(store)
    path = File.join(store, "plan.md")
    log = File.join(tmp, "cache", "gate-blocks.log")

    code = EditGates.dispatch(ctx: block_ctx(path), route: json_deny_route,
                              out: StringIO.new, err: StringIO.new, block_log: log)

    assert_equal 0, code, "the json shape exits 0 by design"
    f = block_fields(log)
    assert_equal 6, f.size
    assert_equal "lock-gate", f[1]
    assert_equal "intent 229 delivery lock is held", f[5],
                 "the rule field is the permissionDecisionReason, not the raw JSON"
  end

  def test_dispatch_writes_an_empty_intent_field_outside_any_intent_dir
    tmp = mktmp("block-log-nointent")
    path = File.join(tmp, "app.rb")
    log = File.join(tmp, "cache", "gate-blocks.log")

    EditGates.dispatch(ctx: block_ctx(path), route: stderr_deny_route,
                       out: StringIO.new, err: StringIO.new, block_log: log)

    f = block_fields(log)
    assert_equal 6, f.size, "an unresolvable intent must not shift the columns"
    assert_equal "", f[3], "the intent field is empty, not omitted"
    assert_equal path, f[4]
  end

  def test_a_failing_block_log_write_changes_nothing
    tmp = mktmp("block-log-fail")
    path = File.join(tmp, "store", "229--demo", "plan.md")
    good = File.join(tmp, "good", "gate-blocks.log")
    # The parent of `bad` is a REGULAR FILE, so FileUtils.mkdir_p raises
    # Errno::ENOTDIR. No chmod, so this behaves identically for root and on
    # every filesystem.
    File.write(File.join(tmp, "wall"), "not a directory\n")
    bad = File.join(tmp, "wall", "gate-blocks.log")

    out_ok = StringIO.new
    err_ok = StringIO.new
    code_ok = EditGates.dispatch(ctx: block_ctx(path), route: stderr_deny_route,
                                 out: out_ok, err: err_ok, block_log: good)

    out_bad = StringIO.new
    err_bad = StringIO.new
    code_bad = EditGates.dispatch(ctx: block_ctx(path), route: stderr_deny_route,
                                  out: out_bad, err: err_bad, block_log: bad)

    assert_equal code_ok, code_bad, "a failing log write must not change the exit code"
    assert_equal out_ok.string, out_bad.string, "stdout must be byte-for-byte identical"
    assert_equal err_ok.string, err_bad.string, "stderr must be byte-for-byte identical"
    assert File.exist?(good)
    refute File.exist?(bad)
  end

  def test_real_dispatcher_logs_a_lock_gate_block
    root = mktmp("block-log-real")
    store = File.join(root, "store")
    intent_dir = File.join(store, "70--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "70--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(root, "INDEX.md"), "## Active\n- [70 - demo](70--demo/70--demo.md)\n\n## Future\n")
    plan_path = File.join(intent_dir, "plan.md")
    home = mktmp("block-log-real-home")

    env = { "PLASTIC_TMP" => mktmp("block-log-real-tmp"), "HOME" => home }
    _out, _err, status = run_dispatcher(
      { "tool_name" => "Write", "tool_input" => { "file_path" => plan_path, "content" => "x\n" } },
      env: env,
    )

    assert_equal 0, status.exitstatus, "lock-gate denies with the json shape, which exits 0"
    log = File.join(home, ".plastic", ".cache", "gate-blocks.log")
    assert File.exist?(log), "a real block must write a block-log line"
    f = File.read(log).lines.first.chomp.split("\t", -1)
    assert_equal 6, f.size
    assert_equal "lock-gate", f[1]
    assert_equal "70", f[3]
    assert_equal plan_path, f[4]
    refute_empty f[5]
  end
end
