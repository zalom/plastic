# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "stringio"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/worktree"

# ACTION_4 (intent 244), chain link 2 of spec D-n's correctness argument. The
# 45 contract tests (ACTION_2) prove the gate LOGIC did not change when it
# moved into scripts/lib/edit_gates.rb; this file proves the merged DISPATCHER
# (scripts/hook-edit-gates) reproduces that logic byte for byte for the SAME
# input as the five retained scripts/hook-* wrappers, including the
# argv-to-stdin translation that only the dispatcher performs (spec AC15).
#
# Every case runs BOTH sides and asserts stdout, stderr and exit code all
# three equal, via Open3.capture3 which never merges the streams: a
# lock-gate deny is stdout JSON at exit 0, a code-gate deny is stderr at
# exit 2, and a merged capture cannot tell them apart.
class EditGatesEquivalenceTest < Minitest::Test
  CODE_GATE = File.expand_path("../scripts/hook-code-gate", __dir__)
  LOCK_GATE = File.expand_path("../scripts/hook-lock-gate", __dir__)
  SAVEPOINT_PRE = File.expand_path("../scripts/hook-savepoint-pre", __dir__)
  LINKS_GATE = File.expand_path("../scripts/hook-links-gate", __dir__)
  CREATE_GATE = File.expand_path("../scripts/hook-create-gate", __dir__)
  DISPATCHER = File.expand_path("../scripts/hook-edit-gates", __dir__)
  EDIT_GATES_LIB = File.expand_path("../scripts/lib/edit_gates.rb", __dir__)
  NEW_INTENT = File.expand_path("../scripts/new-intent", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)

  def setup
    @tmpdirs = []
    @safe_tmp = mktmp("eq-safe-tmp") # empty; never holds a real bridge file
  end

  def teardown
    @tmpdirs.each { |d| FileUtils.rm_rf(d) }
  end

  # --- fixture plumbing -------------------------------------------------------

  def mktmp(name)
    d = Dir.mktmpdir(name)
    @tmpdirs << d
    d
  end

  def silence_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  def with_env(vars)
    saved = {}
    vars.each_key { |k| saved[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def with_neutralized_provision
    real = Worktree.method(:provision)
    Worktree.define_singleton_method(:provision) { |d, *_a, **_kw| d }
    yield
  ensure
    Worktree.define_singleton_method(:provision, real) if real
  end

  # --- subprocess runners, IDENTICAL env on both sides (mandatory: without
  # PLASTIC_HOME/HOME on tmp dirs links-gate scans the real ~/.plastic, and
  # without an explicit PLASTIC_TMP discover_bridge falls through to the real
  # /tmp, a hazard under concurrent background jobs). -------------------------

  def base_env
    { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @safe_tmp, "PLASTIC_HOME" => nil, "HOME" => @safe_tmp }
  end

  def run_argv(script, argv, env: {})
    Open3.capture3(base_env.merge(env), RbConfig.ruby, script, *argv)
  end

  def run_stdin(script, payload, env: {})
    Open3.capture3(base_env.merge(env), RbConfig.ruby, script, stdin_data: JSON.generate(payload))
  end

  # Fix 5 (post-review, intent 244): red-phase proofs mutate a COPY of the
  # shipped scripts/ tree under a tmpdir, never scripts/lib/edit_gates.rb or
  # scripts/hook-edit-gates in the working tree. An interrupt mid-proof must
  # never leave a shipped file corrupted, and parallel test runs must never
  # race on the same file. `overrides` maps a path relative to the repo's
  # scripts/ directory (e.g. "lib/edit_gates.rb") to its mutated content;
  # every other file under scripts/ is copied verbatim, so both the wrapper
  # script and the dispatcher can be run from the SAME copy and still share
  # the one (mutated) library, exactly like the real tree.
  def mutated_scripts_dir(overrides)
    real_scripts = File.expand_path("../scripts", __dir__)
    copy = File.join(mktmp("mutated-scripts"), "scripts")
    FileUtils.cp_r(real_scripts, copy)
    overrides.each { |relative, content| File.write(File.join(copy, relative), content) }
    copy
  end

  def assert_equivalent(wrapper_result, dispatcher_result, label)
    w_out, w_err, w_status = wrapper_result
    d_out, d_err, d_status = dispatcher_result
    assert_equal w_out, d_out, "#{label}: stdout differs\nwrapper=#{w_out.inspect}\ndispatcher=#{d_out.inspect}"
    assert_equal w_err, d_err, "#{label}: stderr differs\nwrapper=#{w_err.inspect}\ndispatcher=#{d_err.inspect}"
    assert_equal w_status.exitstatus, d_status.exitstatus, "#{label}: exit code differs"
  end

  # --- code-gate fixture (Group A cases 1-3, most of Group B) ----------------
  # A pre-How armed derived-key bridge for intent 60 (mirrors code_gate_hook_test).

  def code_gate_fixture
    root = mktmp("eq-code-gate")
    store = File.join(root, "store")
    intent_dir = File.join(store, "60--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "60--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n") # pre-How marker

    project_file = File.join(root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    bridge_tmp = mktmp("eq-code-gate-bridgetmp")
    home = mktmp("eq-code-gate-home")

    with_env("PLASTIC_TMP" => bridge_tmp, "CLAUDE_CODE_SESSION_ID" => nil) do
      with_neutralized_provision do
        silence_stderr do
          Bridge.arm_auto(nil, intent_id: "60", intent_dir: intent_dir, store: store, name: "demo")
        end
      end
    end

    { root: root, store: store, intent_dir: intent_dir, project_file: project_file,
      bridge_tmp: bridge_tmp, home: home }
  end

  # --- lock-gate fixture (Group A cases 4-5, Group B session rows) -----------
  # An ACTIVE intent 61; no lock held unless a test explicitly acquires one.

  def lock_gate_fixture
    root = mktmp("eq-lock-gate")
    store = File.join(root, "store")
    intent_dir = File.join(store, "61--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "61--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(root, "INDEX.md"),
               "## Active\n- [61 — demo](61--demo/61--demo.md)\n\n## Future\n")
    plan_path = File.join(intent_dir, "plan.md")
    home = mktmp("eq-lock-gate-home")
    bridge_tmp = mktmp("eq-lock-gate-bridgetmp")
    { root: root, store: store, intent_dir: intent_dir, plan_path: plan_path,
      home: home, bridge_tmp: bridge_tmp }
  end

  # --- savepoint-pre fixture (Group A cases 6-7) ------------------------------

  def savepoint_fixture
    root = mktmp("eq-savepoint")
    store = File.join(root, "store")
    intent_dir = File.join(store, "62--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "62--demo.md"), "## Intent\nDemo\n")
    { root: root, store: store, intent_dir: intent_dir }
  end

  def ledger_text(intent_dir)
    f = File.join(intent_dir, "savepoint.md")
    File.exist?(f) ? File.read(f) : ""
  end

  def reset_ledger(intent_dir)
    f = File.join(intent_dir, "savepoint.md")
    File.delete(f) if File.exist?(f)
  end

  def normalize_ledger(text)
    text.gsub(/^\S+\s+/, "") # strip the leading ISO-8601 timestamp on each line
  end

  # --- links-gate fixture (Group A cases 8-9): a real born-complete intent so
  # create-gate (which the dispatcher ALSO evaluates, links-gate runs first)
  # agrees ALLOW on the same payload whenever links-gate itself allows. -------

  def links_gate_fixture
    home = mktmp("eq-links-gate-home")
    store = File.join(home, "store")
    FileUtils.mkdir_p(store)
    File.write(File.join(home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n\n## Completed\n")
    out = IO.popen([RbConfig.ruby, NEW_INTENT, "--templates", TEMPLATES,
                    "--store", store, "--intent", "LinksDemo", "--slug", "linksdemo"],
                   err: [:child, :out], &:read)
    intent_dir = out.strip
    raise "new-intent failed: #{out}" unless $?.success?
    intent_file = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    born_complete = File.read(intent_file)
    { home: home, store: store, intent_dir: intent_dir, intent_file: intent_file,
      born_complete: born_complete }
  end

  # --- create-gate fixture (Group A cases 10-12): same recipe as
  # test/create_gate_hook_test.rb, a real born-complete intent from new-intent.

  def create_gate_fixture
    home = mktmp("eq-create-gate-home")
    store = File.join(home, "store")
    FileUtils.mkdir_p(store)
    out = IO.popen([RbConfig.ruby, NEW_INTENT, "--templates", TEMPLATES,
                    "--store", store, "--intent", "CreateDemo", "--slug", "createdemo"],
                   err: [:child, :out], &:read)
    intent_dir = out.strip
    raise "new-intent failed: #{out}" unless $?.success?
    intent_file = File.join(intent_dir, "#{File.basename(intent_dir)}.md")
    born_complete = File.read(intent_file)
    { home: home, store: store, intent_dir: intent_dir, intent_file: intent_file,
      born_complete: born_complete }
  end

  # =====================================================================
  # Group A: the gate matrix (12 cases, floor is 10: 1 allow + 1 deny/gate)
  # =====================================================================

  def test_group_a_case1_code_gate_deny_project_code_pre_how
    fx = code_gate_fixture
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file]], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => fx[:project_file] } }, env: env)
    assert_equivalent(w, d, "case1 code-gate deny")
    assert_equal 2, w[2].exitstatus
    assert_includes w[1], "PLASTIC GATE"
    assert_equal "", w[0]
  end

  def test_group_a_case2_code_gate_allow_under_plastic_home
    fx = code_gate_fixture
    under_plastic = File.join(fx[:home], ".plastic", "store", "INDEX.md")
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [under_plastic], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => under_plastic } }, env: env)
    assert_equivalent(w, d, "case2 code-gate allow under ~/.plastic")
    assert_equal 0, w[2].exitstatus
  end

  def test_group_a_case3_code_gate_allow_via_escape_audits_both_sides
    fx = code_gate_fixture
    content = "puts 1\n# plastic-ok\n"
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    log = File.join(fx[:home], ".plastic", ".cache", "gate-escapes.log")

    w = run_argv(CODE_GATE, [fx[:project_file], "", content], env: env)
    w_log_lines = File.exist?(log) ? File.readlines(log).length : 0
    File.delete(log) if File.exist?(log)

    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => fx[:project_file], "content" => content } },
                  env: env)
    d_log_lines = File.exist?(log) ? File.readlines(log).length : 0

    assert_equivalent(w, d, "case3 code-gate escape allow")
    assert_equal 0, w[2].exitstatus
    assert_equal 1, w_log_lines, "wrapper run must audit the escape exactly once"
    assert_equal 1, d_log_lines, "dispatcher run must audit the escape exactly once"
  end

  def test_group_a_case4_lock_gate_deny_no_lock
    fx = lock_gate_fixture
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(LOCK_GATE, [fx[:plan_path]], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => fx[:plan_path] } }, env: env)
    assert_equivalent(w, d, "case4 lock-gate deny")
    assert_equal 0, w[2].exitstatus
    assert_includes w[0], "\"permissionDecision\":\"deny\""
    assert_equal "", w[1]
  end

  def test_group_a_case5_lock_gate_allow_lock_held
    fx = lock_gate_fixture
    Lock.acquire(fx[:intent_dir], session: "session-1")
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(LOCK_GATE, [fx[:plan_path], "session-1"], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write", "session_id" => "session-1",
                                 "tool_input" => { "file_path" => fx[:plan_path] } }, env: env)
    assert_equivalent(w, d, "case5 lock-gate allow")
    assert_equal 0, w[2].exitstatus
    assert_equal "", w[0]
  end

  def test_group_a_case6_savepoint_pre_append_ledger_matches
    fx = savepoint_fixture
    spec_path = File.join(fx[:intent_dir], "spec.md")
    env = { "HOME" => mktmp("eq-savepoint-home6") }

    w = run_argv(SAVEPOINT_PRE, [spec_path], env: env)
    w_ledger = ledger_text(fx[:intent_dir])
    reset_ledger(fx[:intent_dir])

    d = run_stdin(DISPATCHER, { "tool_name" => "Write", "tool_input" => { "file_path" => spec_path } }, env: env)
    d_ledger = ledger_text(fx[:intent_dir])

    assert_equivalent(w, d, "case6 savepoint-pre append")
    assert_equal 0, w[2].exitstatus
    refute_empty w_ledger
    assert_includes normalize_ledger(w_ledger), "Why  started"
    assert_equal normalize_ledger(w_ledger), normalize_ledger(d_ledger),
                 "ledger content (minus the leading timestamp) must match between the two runs"
  end

  def test_group_a_case7_savepoint_pre_noop_outside_intent_dir
    loose = File.join(mktmp("eq-savepoint-loose"), "loose.md")
    File.write(loose, "x\n")
    env = { "HOME" => mktmp("eq-savepoint-home7") }
    w = run_argv(SAVEPOINT_PRE, [loose], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write", "tool_input" => { "file_path" => loose } }, env: env)
    assert_equivalent(w, d, "case7 savepoint-pre no-op")
    assert_equal 0, w[2].exitstatus
  end

  def test_group_a_case8_links_gate_deny_unbacked_bullet
    fx = links_gate_fixture
    content = fx[:born_complete].sub(
      "<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      "- [[99--nowhere|Nowhere]]\n",
    )
    env = { "PLASTIC_HOME" => fx[:home], "HOME" => mktmp("eq-links-gate-home8") }
    w = run_stdin(LINKS_GATE, { "tool_input" => { "file_path" => fx[:intent_file], "content" => content } }, env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => fx[:intent_file], "content" => content } },
                  env: env)
    assert_equivalent(w, d, "case8 links-gate deny")
    assert_equal 2, w[2].exitstatus
    assert_includes w[1], "PLASTIC LINKS GATE"
  end

  def test_group_a_case9_links_gate_allow_edit_leaves_links_untouched
    fx = links_gate_fixture
    env = { "PLASTIC_HOME" => fx[:home], "HOME" => mktmp("eq-links-gate-home9") }
    payload = { "tool_name" => "Edit",
                "tool_input" => { "file_path" => fx[:intent_file],
                                   "old_string" => "## Intent\nLinksDemo", "new_string" => "## Intent\nLinksDemo, edited" } }
    w = run_stdin(LINKS_GATE, payload, env: env)
    d = run_stdin(DISPATCHER, payload, env: env)
    assert_equivalent(w, d, "case9 links-gate allow, edit leaves Links untouched")
    assert_equal 0, w[2].exitstatus
  end

  def test_group_a_case10_create_gate_deny_missing_chain_full_stderr_equal
    fx = create_gate_fixture
    bad = fx[:born_complete].sub(/^chain:.*\n/, "")
    payload = { "tool_name" => "Write", "tool_input" => { "file_path" => fx[:intent_file], "content" => bad } }
    env = { "HOME" => mktmp("eq-create-gate-home10") }
    w = run_stdin(CREATE_GATE, payload, env: env)
    d = run_stdin(DISPATCHER, payload, env: env)
    assert_equivalent(w, d, "case10 create-gate deny (full stderr equality pins the multi-line shape)")
    assert_equal 2, w[2].exitstatus
    assert_includes w[1], "PLASTIC CREATE GATE"
    assert_includes w[1], "chain"
  end

  def test_group_a_case11_create_gate_allow_born_complete
    fx = create_gate_fixture
    payload = { "tool_name" => "Write",
                "tool_input" => { "file_path" => fx[:intent_file], "content" => fx[:born_complete] } }
    env = { "HOME" => mktmp("eq-create-gate-home11") }
    w = run_stdin(CREATE_GATE, payload, env: env)
    d = run_stdin(DISPATCHER, payload, env: env)
    assert_equivalent(w, d, "case11 create-gate allow born-complete")
    assert_equal 0, w[2].exitstatus
  end

  def test_group_a_case12_create_gate_deny_pathless_missing_file
    home = mktmp("eq-create-gate-home12")
    store = File.join(home, "store")
    FileUtils.mkdir_p(store)
    ghost = File.join(store, "99--ghost", "99--ghost.md")
    payload = { "tool_name" => "Write", "tool_input" => { "file_path" => ghost } }
    env = { "HOME" => home }
    w = run_stdin(CREATE_GATE, payload, env: env)
    d = run_stdin(DISPATCHER, payload, env: env)
    assert_equivalent(w, d, "case12 create-gate deny pathless missing file")
    assert_equal 2, w[2].exitstatus
    assert_includes w[1], "cannot read proposed content"
  end

  # =====================================================================
  # Group B: the argv-to-stdin translation (10 rows, the floor)
  # =====================================================================

  def test_group_b_file_path_straight_through
    fx = code_gate_fixture
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file]], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => fx[:project_file] } }, env: env)
    assert_equivalent(w, d, "group B: file_path straight through")
    assert_equal 2, w[2].exitstatus
  end

  def test_group_b_notebook_path_fallback
    fx = code_gate_fixture
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file]], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "NotebookEdit",
                                 "tool_input" => { "notebook_path" => fx[:project_file] } }, env: env)
    assert_equivalent(w, d, "group B: notebook_path fallback")
    assert_equal 2, w[2].exitstatus
  end

  def test_group_b_relative_path_absolutized_against_cwd
    fx = code_gate_fixture
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file]], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write", "cwd" => fx[:root],
                                 "tool_input" => { "relative_path" => "code/app.rb" } }, env: env)
    assert_equivalent(w, d, "group B: relative_path absolutized against cwd")
    assert_equal 2, w[2].exitstatus
  end

  def test_group_b_project_root_wins_over_cwd
    fx = code_gate_fixture
    decoy = mktmp("eq-decoy-cwd")
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file]], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write", "cwd" => decoy,
                                 "tool_input" => { "relative_path" => "code/app.rb", "project_root" => fx[:root] } },
                  env: env)
    assert_equivalent(w, d, "group B: project_root wins over cwd")
    assert_equal 2, w[2].exitstatus
  end

  def test_group_b_tool_params_fallback_when_tool_input_absent
    fx = code_gate_fixture
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file]], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_params" => { "file_path" => fx[:project_file] } }, env: env)
    assert_equivalent(w, d, "group B: tool_params fallback when tool_input is absent")
    assert_equal 2, w[2].exitstatus
  end

  def test_group_b_session_from_payload
    fx = lock_gate_fixture
    Lock.acquire(fx[:intent_dir], session: "sess-payload")
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(LOCK_GATE, [fx[:plan_path], "sess-payload"], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write", "session_id" => "sess-payload",
                                 "tool_input" => { "file_path" => fx[:plan_path] } }, env: env)
    assert_equivalent(w, d, "group B: session from the payload")
    assert_equal 0, w[2].exitstatus
    assert_equal "", w[0]
  end

  def test_group_b_session_fallback_to_environment
    fx = lock_gate_fixture
    Lock.acquire(fx[:intent_dir], session: "sess-env")
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home], "CLAUDE_CODE_SESSION_ID" => "sess-env" }
    w = run_argv(LOCK_GATE, [fx[:plan_path], ""], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => fx[:plan_path] } }, env: env)
    assert_equivalent(w, d, "group B: session falling back to CLAUDE_CODE_SESSION_ID")
    assert_equal 0, w[2].exitstatus
    assert_equal "", w[0]
  end

  def test_group_b_content_from_content_key
    fx = code_gate_fixture
    content = "puts 1\n# plastic-ok\n"
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file], "", content], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => fx[:project_file], "content" => content } },
                  env: env)
    assert_equivalent(w, d, "group B: content from the content key")
    assert_equal 0, w[2].exitstatus
  end

  def test_group_b_content_from_new_string_fallback_when_content_absent
    fx = code_gate_fixture
    value = "puts 1\n# plastic-ok\n"
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file], "", value], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write",
                                 "tool_input" => { "file_path" => fx[:project_file],
                                                    "old_string" => "puts 1\n", "new_string" => value } },
                  env: env)
    assert_equivalent(w, d, "group B: content falling back to new_string when content is absent")
    assert_equal 0, w[2].exitstatus
  end

  def test_group_b_empty_path_allows_both_sides
    env = { "PLASTIC_TMP" => mktmp("eq-empty-tmp"), "HOME" => mktmp("eq-empty-home") }
    w = run_argv(CODE_GATE, [""], env: env)
    d = run_stdin(DISPATCHER, { "tool_name" => "Write", "tool_input" => { "file_path" => "" } }, env: env)
    assert_equivalent(w, d, "group B: empty path allows on both sides")
    assert_equal 0, w[2].exitstatus
    assert_equal "", w[0]
    assert_equal "", w[1]
  end

  # Fix 3 (post-review, intent 244): per-key tool_input/tool_params fallback
  # for file_path, restored after review found the merged context_from's
  # whole-object pick silently dropped it. tool_input: {} is an empty but
  # TRUTHY hash, so a whole-object pick (`tool_input || tool_params`) never
  # even looks at tool_params; the old links-gate/create-gate wrappers read
  # `dig("tool_input","file_path") || dig("tool_params","file_path")`, each
  # KEY falling back independently, and still find file_path in tool_params.
  # create-gate's pathless-missing-file deny (case12's shape) is the
  # observable proof: a broken (nil) file_path allows immediately, while the
  # correctly-resolved ghost path is judged and denied.
  def test_group_b_tool_input_empty_hash_tool_params_carries_file_path
    home = mktmp("eq-fix3-create-gate-home")
    store = File.join(home, "store")
    FileUtils.mkdir_p(store)
    ghost = File.join(store, "99--ghost", "99--ghost.md")
    payload = { "tool_name" => "Write", "tool_input" => {}, "tool_params" => { "file_path" => ghost } }
    env = { "HOME" => home }
    w = run_stdin(CREATE_GATE, payload, env: env)
    d = run_stdin(DISPATCHER, payload, env: env)
    assert_equivalent(w, d, "group B: tool_input empty hash, tool_params carries file_path")
    assert_equal 2, w[2].exitstatus,
                 "sanity: this payload must actually be JUDGED (denied), not silently allowed " \
                 "(a broken file_path read would allow immediately instead)"
    assert_includes w[1], "cannot read proposed content"
  end

  # =====================================================================
  # Red-phase proofs (intent 208: a check that cannot fail is not a check)
  # =====================================================================

  # Proof 1: a message-text-only change stays GREEN here. This is the honest
  # limit of a differential test (both sides read the SAME live library), and
  # exactly why ACTION_2's 45 untouched contract tests remain the bar on
  # message TEXT; this file's job is structural equivalence, not text pinning.
  def test_red_phase_proof_1_message_text_change_stays_green
    original = File.read(EDIT_GATES_LIB)
    mutated = original.sub('"PLASTIC GATE — #{reason}"', '"PLASTIC GATE - #{reason}"')
    refute_equal original, mutated, "sanity: the mutation must actually change the file"
    copy_dir = mutated_scripts_dir("lib/edit_gates.rb" => mutated)
    code_gate_copy = File.join(copy_dir, "hook-code-gate")
    dispatcher_copy = File.join(copy_dir, "hook-edit-gates")

    fx = code_gate_fixture
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(code_gate_copy, [fx[:project_file]], env: env)
    d = run_stdin(dispatcher_copy, { "tool_name" => "Write",
                                      "tool_input" => { "file_path" => fx[:project_file] } }, env: env)
    assert_equal w[0], d[0]
    assert_equal w[1], d[1]
    assert_equal w[2].exitstatus, d[2].exitstatus
    assert_includes w[1], "PLASTIC GATE - ",
                    "sanity: both sides now emit the hyphenated message, undetectable by this file"
  end

  # Proof 2: deleting the "code-gate" arm from the dispatcher's case/when must
  # turn cases 1 and 3 red. Case 1's streams flip (dispatcher wrongly allows
  # where the wrapper denies). Case 3's exit/streams coincidentally still
  # match (both allow), so it is the escape-log assertion specifically that
  # catches the missing arm: the dispatcher never calls code_gate at all once
  # its arm is gone, so it audits zero lines while the wrapper still audits
  # exactly one.
  def test_red_phase_proof_2_removing_the_code_gate_arm_turns_cases_1_and_3_red
    original = File.read(DISPATCHER)
    mutated = original.lines.reject { |l| l.include?('when "code-gate"') }.join
    refute_equal original, mutated, "sanity: the mutation must actually remove the arm"
    copy_dir = mutated_scripts_dir("hook-edit-gates" => mutated)
    dispatcher_copy = File.join(copy_dir, "hook-edit-gates")

    fx1 = code_gate_fixture
    env1 = { "PLASTIC_TMP" => fx1[:bridge_tmp], "HOME" => fx1[:home] }
    w1 = run_argv(CODE_GATE, [fx1[:project_file]], env: env1)
    d1 = run_stdin(dispatcher_copy, { "tool_name" => "Write",
                                       "tool_input" => { "file_path" => fx1[:project_file] } }, env: env1)
    case1_mismatch = (w1[0] != d1[0]) || (w1[1] != d1[1]) || (w1[2].exitstatus != d1[2].exitstatus)
    assert case1_mismatch, "case 1 must go RED when the code-gate arm is removed " \
                            "(the dispatcher wrongly allows what the wrapper denies)"

    fx3 = code_gate_fixture
    content = "puts 1\n# plastic-ok\n"
    env3 = { "PLASTIC_TMP" => fx3[:bridge_tmp], "HOME" => fx3[:home] }
    log = File.join(fx3[:home], ".plastic", ".cache", "gate-escapes.log")
    w3 = run_argv(CODE_GATE, [fx3[:project_file], "", content], env: env3)
    w3_log_lines = File.exist?(log) ? File.readlines(log).length : 0
    File.delete(log) if File.exist?(log)
    run_stdin(dispatcher_copy, { "tool_name" => "Write",
                                  "tool_input" => { "file_path" => fx3[:project_file], "content" => content } },
              env: env3)
    d3_log_lines = File.exist?(log) ? File.readlines(log).length : 0
    assert w3_log_lines != d3_log_lines,
           "case 3's escape-log assertion must go RED: the dispatcher never calls code_gate " \
           "at all once its arm is removed, so it audits zero lines while the wrapper still " \
           "audits one (#{w3_log_lines} vs #{d3_log_lines})"
  end

  # Proof 3: dropping project_root from context_from's absolutization must
  # turn the Group B "project_root wins over cwd" row red.
  def test_red_phase_proof_3_dropping_project_root_turns_the_group_b_row_red
    original = File.read(EDIT_GATES_LIB)
    mutated = original.sub(
      'root = input["project_root"] || payload["cwd"] || ""',
      'root = payload["cwd"] || ""',
    )
    refute_equal original, mutated, "sanity: the mutation must actually drop the project_root term"
    copy_dir = mutated_scripts_dir("lib/edit_gates.rb" => mutated)
    dispatcher_copy = File.join(copy_dir, "hook-edit-gates")

    fx = code_gate_fixture
    decoy = mktmp("eq-decoy-cwd-proof3")
    env = { "PLASTIC_TMP" => fx[:bridge_tmp], "HOME" => fx[:home] }
    w = run_argv(CODE_GATE, [fx[:project_file]], env: env)
    d = run_stdin(dispatcher_copy, { "tool_name" => "Write", "cwd" => decoy,
                                      "tool_input" => { "relative_path" => "code/app.rb",
                                                         "project_root" => fx[:root] } }, env: env)
    mismatch = (w[0] != d[0]) || (w[1] != d[1]) || (w[2].exitstatus != d[2].exitstatus)
    assert mismatch, "the project_root row must go RED once project_root is dropped from context_from"
  end
end
