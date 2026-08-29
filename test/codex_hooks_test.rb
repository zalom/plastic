# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require "rbconfig"
require "open3"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/worktree"

# Codex dispatcher shim (intent 102, Step 3): drives the real scripts/codex-hook
# as a subprocess, feeding Codex-shaped stdin JSON fixtures (guide Part 4) whose
# tool_input.command carries a hand-built apply_patch V4A envelope. Mirrors the
# existing Claude hook subprocess test pattern (test/gate_check_test.rb,
# test/lock_gate_hook_test.rb, test/code_gate_hook_test.rb,
# test/savepoint_pre_hook_test.rb) but drives each gate through the ONE Codex
# dispatcher instead of the bash-shim-fed core directly. No live Codex anywhere
# (Decision 14): every fixture is hand-built to the guide's documented shapes.
class CodexHooksTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/codex-hook", __dir__)

  def setup
    @root = Dir.mktmpdir("codex-hook")
    @store = File.join(@root, "store")
    FileUtils.mkdir_p(@store)
    @bridge_tmp = Dir.mktmpdir("codex-hook-tmp")
    @fake_home = Dir.mktmpdir("codex-hook-home")
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    @saved_plastic_tmp = ENV["PLASTIC_TMP"]
    ENV["PLASTIC_TMP"] = @bridge_tmp
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
    Worktree.define_singleton_method(:provision, @real_provision) if @real_provision
  end

  def silence_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  # --- apply_patch V4A envelope fixture builders (the same shape the parser expects) ---

  def add_section(path, content)
    lines = content.to_s.each_line.map { |l| "+#{l.chomp}" }
    "*** Add File: #{path}\n#{lines.join("\n")}\n"
  end

  def update_section(path, added_lines)
    lines = Array(added_lines).map { |l| "+#{l}" }
    "*** Update File: #{path}\n@@\n#{lines.join("\n")}\n"
  end

  def patch(*sections)
    "*** Begin Patch\n#{sections.join}*** End Patch\n"
  end

  # --- Codex hook stdin payload (guide Part 4 field set) ---

  def codex_payload(command, session_id: "", event: "PreToolUse")
    {
      "session_id" => session_id.to_s,
      "transcript_path" => "/tmp/transcript",
      "cwd" => @store,
      "hook_event_name" => event,
      "model" => "test-model",
      "permission_mode" => "default",
      "turn_id" => "turn-1",
      "tool_name" => "apply_patch",
      "tool_use_id" => "tool-1",
      "tool_input" => { "command" => command },
    }
  end

  # --- Codex hook stdin payload for the three live-state events (intent 199) ---
  # No tool_input at all: these are not tool calls. `user_prompt` is the one
  # event-specific field, carried only for UserPromptSubmit (the guide confirms
  # Codex uses "the same schema, same behavior" as Claude here).

  def state_payload(event:, session_id: "", user_prompt: nil, cwd: @store)
    payload = {
      "session_id" => session_id.to_s,
      "transcript_path" => "/tmp/transcript",
      "cwd" => cwd,
      "hook_event_name" => event,
      "model" => "test-model",
      "permission_mode" => "default",
      "turn_id" => "turn-1",
    }
    payload["user_prompt"] = user_prompt unless user_prompt.nil?
    payload
  end

  def run_hook(gate, payload_hash, session: nil, chdir: @store, home: @fake_home,
               plastic_home: nil, script: SCRIPT, extra_env: {})
    env = { "PLASTIC_TMP" => @bridge_tmp, "CLAUDE_CODE_SESSION_ID" => session, "HOME" => home }
    env["PLASTIC_HOME"] = plastic_home if plastic_home
    env.merge!(extra_env)
    out = nil
    IO.popen(env, [RbConfig.ruby, script, gate], "r+", err: [:child, :out], chdir: chdir) do |io|
      io.write(payload_hash.nil? ? "" : JSON.generate(payload_hash))
      io.close_write
      out = io.read
    end
    [out, $?]
  end

  # ---- fixtures ----

  def valid_intent_content
    <<~MD
      ---
      id: "1"
      intent: "Demo intent"
      sources: []
      chain: []
      created: 2026-01-01
      author: test
      tags: []
      ---

      ## Intent
      Demo

      ## Context
      Demo

      ## Outcome
      (pending)

      ## Insights
      (none)

      ## Links
      (none)
    MD
  end

  def malformed_intent_content
    "---\nid: \"1\"\n---\n\n## Intent\nDemo\n"
  end

  # ---- create-gate ----
  #
  # Intent 251: five registered per-gate commands became one edit-gates
  # dispatcher. The per-gate names cannot survive as unregistered dispatcher
  # arms, because doctor reports those as dead code Codex never reaches
  # (intent 200). Per-gate isolation now lives in test/codex_edit_gates_test.rb,
  # which drives CodexEditGates in-process; the tests below still prove the
  # SAME decisions, reached through the one real subprocess dispatcher, with
  # only the gate argument changed per intent 244 D-n (a regression bar you
  # have to modify to make it pass is not a bar).

  def test_create_gate_blocks_malformed_add
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, malformed_intent_content))
    out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 2, status.exitstatus, "malformed intent Add must be blocked: #{out}"
    assert_includes out, "PLASTIC CREATE GATE"
  end

  def test_create_gate_allows_valid_add
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, valid_intent_content))
    _out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 0, status.exitstatus
  end

  def test_create_gate_defers_update_of_intent_file
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(update_section(intent_path, ["broken frontmatter, would fail if validated"]))
    _out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 0, status.exitstatus, "Update ops must defer to the PostToolUse backstop"
  end

  def test_create_gate_allows_non_intent_path
    non_intent = File.join(@store, "1--demo", "spec.md")
    body = patch(add_section(non_intent, malformed_intent_content))
    _out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 0, status.exitstatus, "a non-intent-file path must never be judged by create-gate"
  end

  # ---- lock-gate ----

  def test_lock_gate_denies_with_no_live_lock
    intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"), "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")

    plan = File.join(intent_dir, "plan.md")
    body = patch(update_section(plan, ["content"]))
    out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 0, status.exitstatus, "lock-gate must never exit non-zero"
    assert_includes out, '"permissionDecision":"deny"'
  end

  def test_lock_gate_allows_when_lock_held
    intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"), "## Active\n- [96 — demo](96--demo/96--demo.md)\n\n## Future\n")

    session = "test-#{Process.pid}-#{object_id}"
    silence_stderr do
      Bridge.arm_guided(session, intent_id: "96", intent_dir: intent_dir, store: @store, name: "demo")
    end

    plan = File.join(intent_dir, "plan.md")
    body = patch(update_section(plan, ["content"]))
    out, status = run_hook("edit-gates", codex_payload(body, session_id: session), session: session)
    assert_equal 0, status.exitstatus
    refute_includes out, '"permissionDecision":"deny"', "held lock must allow silently: #{out}"
  end

  def test_lock_gate_denies_fresh_foreign_lock_naming_dollar_prefix
    intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"), "## Active\n- [96 - demo](96--demo/96--demo.md)\n\n## Future\n")

    Lock.acquire(intent_dir, session: "other-session")

    plan = File.join(intent_dir, "plan.md")
    body = patch(update_section(plan, ["content"]))
    out, status = run_hook("edit-gates", codex_payload(body, session_id: "me"), session: "me")
    assert_equal 0, status.exitstatus, "lock-gate must never exit non-zero"
    assert_includes out, '"permissionDecision":"deny"'
    assert_includes out, "$plastic-doctor check the lock status"
    refute_includes out, "/plastic-doctor"
  end

  # ---- code-gate ----

  def test_code_gate_blocks_pre_how_project_edit
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n") # stage why, pre-How

    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo") }

    body = patch(update_section(project_file, ["puts 2"]))
    _out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 2, status.exitstatus, "pre-How project edit should be blocked"
  end

  def test_code_gate_allows_plastic_ok_escape
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n")

    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo") }

    body = patch(update_section(project_file, ["puts 2", "# plastic-ok"]))
    _out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 0, status.exitstatus, "trailing # plastic-ok must allow the edit"
  end

  # ---- record ----

  # Intent 298: record never blocks. A plan.md-before-spec.md write that used to
  # trip gate-check's exit 2 now exits 0 with no decision key at all.
  def test_record_never_blocks_a_condition_that_used_to_gate
    intent_dir = File.join(@store, "97--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "97--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"), "## Active\n- [97 - demo](97--demo/97--demo.md)\n\n## Future\n")

    session = "test-#{Process.pid}-#{object_id}"
    silence_stderr do
      Bridge.arm_guided(session, intent_id: "97", intent_dir: intent_dir, store: @store, name: "demo")
    end

    plan = File.join(intent_dir, "plan.md")
    body = patch(add_section(plan, "# Plan\n"))
    out, status = run_hook("record", codex_payload(body, session_id: session, event: "PostToolUse"), session: session)
    assert_equal 0, status.exitstatus, "record must never block: #{out}"
    refute_includes out, '"decision"'
  end

  def test_record_allows_valid_stage_write_and_appends_savepoint
    intent_dir = File.join(@store, "98--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "98--demo.md"), "## Intent\nDemo\n")
    spec = File.join(intent_dir, "spec.md")
    File.write(spec, "# Spec\nreal\n")

    body = patch(add_section(spec, "# Spec\nreal\n"))
    _out, status = run_hook("record", codex_payload(body))
    assert_equal 0, status.exitstatus

    ledger = File.read(File.join(intent_dir, "savepoint.md"))
    assert_includes ledger, "spec.md created"
  end

  # ---- savepoint-pre ----

  def test_savepoint_pre_appends_started_and_never_blocks
    intent_dir = File.join(@store, "81--x")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "81--x.md"), "## Intent\nx\n")

    spec = File.join(intent_dir, "spec.md")
    body = patch(add_section(spec, "content"))
    _out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 0, status.exitstatus

    ledger = File.read(File.join(intent_dir, "savepoint.md"))
    assert_includes ledger, "Why  started"
  end

  # ---- links-gate ----

  def links_intent_content(id:, body_line: "Body.")
    <<~MD
      ---
      id: "#{id}"
      intent: "Demo"
      sources: []
      chain: []
      created: 2026-01-01
      author: test
      tags: []
      ---

      ## Intent
      #{body_line}

      ## Links
      <!-- No sources or chain; this intent has no graph edges to project. -->
    MD
  end

  def test_links_gate_denies_a_hand_typed_links_section
    intent_dir = File.join(@store, "70--demo")
    FileUtils.mkdir_p(intent_dir)
    intent_path = File.join(intent_dir, "70--demo.md")
    before = links_intent_content(id: "70")
    File.write(intent_path, before)

    after = before.sub(
      "<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      "- [[99--nowhere|Nowhere]]\n"
    )

    body = patch(update_section(intent_path, after.each_line.map(&:chomp)))
    out, status = run_hook("edit-gates", codex_payload(body), plastic_home: @root)

    assert_equal 2, status.exitstatus, "hand-typed unbacked Links line must be denied: #{out}"
    assert_includes out, "PLASTIC LINKS GATE"
  end

  def test_links_gate_allows_an_edit_that_leaves_links_untouched
    intent_dir = File.join(@store, "71--demo")
    FileUtils.mkdir_p(intent_dir)
    intent_path = File.join(intent_dir, "71--demo.md")
    before = links_intent_content(id: "71")
    File.write(intent_path, before)

    after = before.sub("Body.", "Body, edited.")

    body = patch(update_section(intent_path, after.each_line.map(&:chomp)))
    _out, status = run_hook("edit-gates", codex_payload(body), plastic_home: @root)

    assert_equal 0, status.exitstatus, "an edit that never touches ## Links must be allowed"
  end

  # ---- multi-file veto ----

  def test_multi_file_patch_denied_when_one_file_violates
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n")

    violating_file = File.join(@root, "code", "bad.rb")
    clean_file = File.join(@root, "code", "clean.rb")
    FileUtils.mkdir_p(File.dirname(violating_file))
    File.write(violating_file, "puts 2\n")
    File.write(clean_file, "puts 1\n")

    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo") }

    # violating_file first (no escape): the dispatcher must deny the whole call
    # on this first violation, never reaching clean_file (escaped, would pass alone).
    body = patch(update_section(violating_file, ["bad"]), update_section(clean_file, ["ok", "# plastic-ok"]))
    _out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 2, status.exitstatus, "one violating file in a bundle must deny the whole apply_patch"
  end

  # ---- live-state events (intent 199): SessionStart, UserPromptSubmit, PreCompact ----

  # hook-session-start shells out to ~/.plastic/scripts/read-config for the
  # stale-intent threshold (no CLAUDE_PLUGIN_ROOT on Codex, so it always takes
  # the ~/.plastic branch). A fake $HOME with no installed scripts/ makes that
  # shell-out fail with a noisy "No such file" on stderr, which run_hook's
  # merged out+err would fold into the captured JSON. Same shim pattern
  # test/deprecation_display_test.rb already uses for the identical gap.
  def write_read_config_shim(plastic_home)
    shim = <<~'RUBY'
      #!/usr/bin/env ruby
      key = ARGV[0]
      value = key == "stale_threshold_days" ? 3 : nil
      puts value.nil? ? "" : value.to_s
    RUBY
    path = File.join(plastic_home, "scripts", "read-config")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, shim)
    File.chmod(0o755, path)
  end

  # hooks/check-update shells out to a real `npm view @zalom/plastic dist-tags`. Tests never
  # call an external service, so PATH gets a fake npm that just sleeps: that is also exactly
  # the slow-network condition intent 289 is about, made deterministic. Returns the bin dir
  # to prepend to PATH.
  def stub_npm_bin(sleep_seconds)
    bin = File.join(@root, "stub-bin")
    FileUtils.mkdir_p(bin)
    path = File.join(bin, "npm")
    File.write(path, "#!/bin/bash\nsleep #{sleep_seconds}\nexit 0\n")
    File.chmod(0o755, path)
    bin
  end

  def path_with(bin)
    { "PATH" => "#{bin}:#{ENV["PATH"]}" }
  end

  def test_session_start_returns_plastic_context
    plastic_home = File.join(@fake_home, ".plastic")
    FileUtils.mkdir_p(plastic_home)
    File.write(File.join(plastic_home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n")
    write_read_config_shim(plastic_home)

    out, status = run_hook("session-start", state_payload(event: "SessionStart"))
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Plastic Core loaded",
      "must carry the same boot banner Claude gets from hook-session-start"
  end

  def test_check_update_is_silent_and_never_blocks
    plastic_home = File.join(@fake_home, ".plastic")
    FileUtils.mkdir_p(plastic_home)
    File.write(File.join(plastic_home, "VERSION"), "1.0.0\n")
    bin = stub_npm_bin(10)

    out, status = run_hook("check-update", state_payload(event: "SessionStart"),
                           plastic_home: plastic_home, extra_env: path_with(bin))
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "check-update only writes a background cache file, never additionalContext"
  end

  # Intent 289. The launcher's own exit must release this dispatcher's pipes. Before the
  # fix, the backgrounded npm call held them, so capture3 blocked until the 5 s timeout,
  # closed the pipes under its reader threads, and their IOError backtraces landed in the
  # merged output this helper captures. That is the CI flake (run 32776005720).
  def test_check_update_launcher_releases_dispatcher_pipes_immediately
    plastic_home = File.join(@fake_home, ".plastic")
    FileUtils.mkdir_p(plastic_home)
    File.write(File.join(plastic_home, "VERSION"), "1.0.0\n")
    bin = stub_npm_bin(10)

    started = Time.now
    out, status = run_hook("check-update", state_payload(event: "SessionStart"),
                           plastic_home: plastic_home, extra_env: path_with(bin))
    elapsed = Time.now - started

    assert_equal 0, status.exitstatus
    assert_empty out.strip,
      "a slow background update check must never leak reader-thread noise into hook output"
    assert_operator elapsed, :<, 3.0,
      "the dispatcher must return when the launcher exits, not when the npm call finishes"
  end

  # Intent 289, belt. Any launcher that leaks the dispatcher's pipes, including an older
  # installed copy, must time out SILENTLY. The dispatcher resolves a state-hook launcher as
  # __dir__/../hooks/<gate> (scripts/codex-hook:66) and requires nothing outside stdlib on
  # that branch, so copying the one file beside a fake hooks/ dir is enough to point it at a
  # launcher of our choosing. The copy needs no exec bit: run_hook invokes it via RbConfig.ruby.
  def test_state_hook_timeout_stays_silent
    fake = File.join(@root, "fake-install")
    FileUtils.mkdir_p(File.join(fake, "scripts"))
    FileUtils.mkdir_p(File.join(fake, "hooks"))
    dispatcher = File.join(fake, "scripts", "codex-hook")
    FileUtils.cp(SCRIPT, dispatcher)
    launcher = File.join(fake, "hooks", "check-update")
    # Deliberately leaky: exits at once, leaves a child holding the inherited pipes. The
    # exact shape hooks/check-update had before this intent.
    File.write(launcher, "#!/bin/bash\n( sleep 10 ) &\nexit 0\n")
    File.chmod(0o755, launcher)

    started = Time.now
    out, status = run_hook("check-update", state_payload(event: "SessionStart"),
                           script: dispatcher)
    elapsed = Time.now - started

    assert_equal 0, status.exitstatus,
      "a timed-out launcher must still fail open with exit 0"
    assert_empty out.strip,
      "the timeout path must print no Open3 reader-thread backtrace (stream closed in another thread)"
    assert_operator elapsed, :>=, 4.0,
      "the fixture must actually hold the pipes past STATE_TIMEOUT, or this test proves nothing"
  end

  # ---- capture (intent 298 merges continue, future-intent-check, auto-arm) ----

  def test_capture_continue_returns_dashboard_context
    plastic_home = File.join(@fake_home, ".plastic")
    FileUtils.mkdir_p(File.join(plastic_home, "store"))
    File.write(File.join(plastic_home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n")

    payload = state_payload(event: "UserPromptSubmit", user_prompt: "continue")
    out, status = run_hook("capture", payload)
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "plastic-continuing skill workflow"
  end

  def test_capture_matches_a_future_intent_keyword
    plastic_home = File.join(@fake_home, ".plastic")
    intent_dir = File.join(plastic_home, "store", "50--demo-widget")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "50--demo-widget.md"), <<~MD)
      ---
      id: "50"
      intent: "Demo widget feature"
      tags: ["widget"]
      created: 2026-01-01
      author: test
      ---
      ## Intent
      Demo widget
    MD
    File.write(File.join(plastic_home, "INDEX.md"),
      "# Index\n\n## Active\n\n## Future\n- [50 - Demo widget feature](store/50--demo-widget/50--demo-widget.md)\n")

    payload = state_payload(event: "UserPromptSubmit", user_prompt: "let's talk about the widget feature today")
    out, status = run_hook("capture", payload)
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Future intents related to this message"
    assert_includes ctx, "widget"
  end

  def test_capture_flags_auto_trigger_phrase
    payload = state_payload(event: "UserPromptSubmit", user_prompt: "take it from here")
    out, status = run_hook("capture", payload)
    assert_equal 0, status.exitstatus
    ctx = JSON.parse(out).dig("hookSpecificOutput", "additionalContext")
    assert_includes ctx, "Invoke the plastic-auto skill"
  end

  def test_power_tools_hook_never_blocks_regardless_of_qmd_presence
    plastic_home = File.join(@fake_home, ".plastic")
    FileUtils.mkdir_p(plastic_home)
    File.write(File.join(plastic_home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n")

    payload = state_payload(event: "UserPromptSubmit", user_prompt: "what should I work on next in this project")
    out, status = run_hook("power-tools", payload)
    assert_equal 0, status.exitstatus
    # qmd may or may not be on PATH in the run environment; either way the dispatcher
    # must relay valid JSON or nothing, never crash, never hang.
    JSON.parse(out) unless out.to_s.strip.empty?
  end

  def test_savepoint_hook_matches_claude_static_payload
    claude_launcher = File.expand_path("../hooks/savepoint", __dir__)
    expected, _err, _claude_status = Open3.capture3(claude_launcher)

    out, status = run_hook("savepoint", state_payload(event: "PreCompact"))
    assert_equal 0, status.exitstatus
    assert_equal JSON.parse(expected), JSON.parse(out),
      "Codex's PreCompact savepoint hook must produce the identical payload Claude's PreCompact hook produces"
    assert_includes JSON.parse(out)["systemMessage"], "PLASTIC SAVEPOINT"
  end

  # ---- Codex hook stdin payload for the Bash-tool gates (intent 203) ----
  # tool_name is "Bash" (D1, confirmed against the official Codex hooks doc),
  # NOT "apply_patch": these two gate names never go through ApplyPatchEnvelope.

  def codex_bash_payload(command, session_id: "", cwd: @store)
    {
      "session_id" => session_id.to_s,
      "transcript_path" => "/tmp/transcript",
      "cwd" => cwd,
      "hook_event_name" => "PreToolUse",
      "model" => "test-model",
      "permission_mode" => "default",
      "turn_id" => "turn-1",
      "tool_name" => "Bash",
      "tool_use_id" => "tool-1",
      "tool_input" => { "command" => command },
    }
  end

  # ---- bash-gate (intent 203): the Bash-tool dispatch path ----

  def test_bash_gate_denies_a_pre_how_shell_write_to_project_code
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n") # stage Why, pre-How

    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo") }

    command = "echo 'puts 2' > #{project_file}"
    out, status = run_hook("bash-gate", codex_bash_payload(command))
    assert_equal 2, status.exitstatus, "a pre-How shell write to project code must be DENIED: #{out}"
    assert_includes out, "PLASTIC GATE"
  end

  def test_bash_gate_allows_the_plastic_ok_escape_and_logs_it
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n")

    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")

    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo") }

    command = "echo 'puts 2' > #{project_file} # plastic-ok"
    out, status = run_hook("bash-gate", codex_bash_payload(command, session_id: "codex-esc"), session: "codex-esc")
    assert_equal 0, status.exitstatus, "the audited escape must allow the write: #{out}"

    log = File.join(@fake_home, ".plastic", ".cache", "gate-escapes.log")
    assert File.exist?(log), "the escape must be audited on Codex too, identically to Claude"
    assert_includes File.read(log), "codex-esc"
  end

  def test_bash_gate_allows_a_read_only_command
    _out, status = run_hook("bash-gate", codex_bash_payload("cat app.rb"))
    assert_equal 0, status.exitstatus
  end

  # ---- adversarial fail-open for the Bash-tool path (mirrors Decision 14) ----

  def test_bash_gate_malformed_stdin_fails_open
    env = { "PLASTIC_TMP" => @bridge_tmp, "HOME" => @fake_home }
    out = nil
    IO.popen(env, [RbConfig.ruby, SCRIPT, "bash-gate"], "r+", err: [:child, :out]) do |io|
      io.write("not valid json{{{")
      io.close_write
      out = io.read
    end
    assert_equal 0, $?.exitstatus, out
  end

  # ---- live-state adversarial fail-open (intent 199, mirrors Decision 14) ----

  def test_state_hook_malformed_stdin_fails_open
    env = { "PLASTIC_TMP" => @bridge_tmp, "HOME" => @fake_home }
    out = nil
    IO.popen(env, [RbConfig.ruby, SCRIPT, "session-start"], "r+", err: [:child, :out]) do |io|
      io.write("not valid json{{{")
      io.close_write
      out = io.read
    end
    assert_equal 0, $?.exitstatus
    assert_empty out.strip
  end

  def test_state_hook_missing_session_id_does_not_crash
    payload = state_payload(event: "UserPromptSubmit", user_prompt: "hello there friend, nothing to see")
    payload.delete("session_id")
    out, status = run_hook("capture", payload)
    assert_equal 0, status.exitstatus
    assert_empty out.strip, "no trigger phrase and no session bridge -> silent, never a crash"
  end

  def test_unrecognized_hook_name_with_state_shaped_stdin_fails_open
    payload = state_payload(event: "SessionStart")
    out, status = run_hook("not-a-real-hook", payload)
    assert_equal 0, status.exitstatus
    assert_empty out.strip
  end

  # ---- adversarial fail-open (Decision 14, no live Codex) ----

  def test_missing_tool_input_fails_open
    _out, status = run_hook("edit-gates", { "session_id" => "" })
    assert_equal 0, status.exitstatus
  end

  def test_missing_session_id_fails_open
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, valid_intent_content))
    payload = codex_payload(body)
    payload.delete("session_id")
    _out, status = run_hook("edit-gates", payload)
    assert_equal 0, status.exitstatus
  end

  def test_empty_command_fails_open
    _out, status = run_hook("edit-gates", codex_payload(""))
    assert_equal 0, status.exitstatus
  end

  def test_non_apply_patch_command_fails_open
    _out, status = run_hook("edit-gates", codex_payload("rm -rf /"))
    assert_equal 0, status.exitstatus
  end

  def test_unknown_gate_arg_fails_open
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, valid_intent_content))
    _out, status = run_hook("not-a-real-gate", codex_payload(body))
    assert_equal 0, status.exitstatus
  end

  def test_empty_stdin_fails_open
    env = { "PLASTIC_TMP" => @bridge_tmp, "HOME" => @fake_home }
    out = nil
    IO.popen(env, [RbConfig.ruby, SCRIPT, "edit-gates"], "r+", err: [:child, :out]) do |io|
      io.close_write
      out = io.read
    end
    assert_equal 0, $?.exitstatus, out
  end

  # ---- merged dispatcher (intent 251) ----

  # Order matters here (unlike the other four scenarios, this one shares a
  # single @store/@bridge_tmp across all four probes): code-gate's
  # Bridge.arm_auto plants a REAL delivery.lock for intent 52, and lock-gate's
  # solo-delivery relaxation (intent 128) scans the whole store for any fresh
  # delivery lock and, finding exactly one, treats it as confirmed solo mode
  # and ALLOWS an unrelated intent's otherwise-undenied write. So code-gate
  # runs LAST, after every probe that depends on "no live lock anywhere yet".
  def test_edit_gates_runs_every_gate_on_one_apply_patch_payload
    # lock-gate
    lock_intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(lock_intent_dir)
    File.write(File.join(lock_intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"), "## Active\n- [96 - demo](96--demo/96--demo.md)\n\n## Future\n")
    plan = File.join(lock_intent_dir, "plan.md")
    body = patch(update_section(plan, ["content"]))
    out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 0, status.exitstatus, "lock-gate: #{out}"
    assert_includes out, '"permissionDecision":"deny"'

    # links-gate
    links_intent_dir = File.join(@store, "70--demo")
    FileUtils.mkdir_p(links_intent_dir)
    intent_path = File.join(links_intent_dir, "70--demo.md")
    before = links_intent_content(id: "70")
    File.write(intent_path, before)
    after = before.sub(
      "<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      "- [[99--nowhere|Nowhere]]\n"
    )
    body = patch(update_section(intent_path, after.each_line.map(&:chomp)))
    out, status = run_hook("edit-gates", codex_payload(body), plastic_home: @root)
    assert_equal 2, status.exitstatus, "links-gate: #{out}"
    assert_includes out, "PLASTIC LINKS GATE"

    # create-gate
    malformed_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(malformed_path, malformed_intent_content))
    out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 2, status.exitstatus, "create-gate: #{out}"
    assert_includes out, "PLASTIC CREATE GATE"

    # code-gate (last: see the method comment)
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n")
    project_file = File.join(@root, "code", "app.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")
    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo") }

    body = patch(update_section(project_file, ["puts 2"]))
    out, status = run_hook("edit-gates", codex_payload(body))
    assert_equal 2, status.exitstatus, "code-gate: #{out}"
    assert_includes out, "PLASTIC GATE"
  end

  def test_savepoint_pre_still_appends_when_a_later_op_is_denied
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n") # stage Why, pre-How
    project_file = File.join(@root, "code", "bad.rb")
    FileUtils.mkdir_p(File.dirname(project_file))
    File.write(project_file, "puts 1\n")
    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo") }

    other_intent_dir = File.join(@store, "81--x")
    FileUtils.mkdir_p(other_intent_dir)
    File.write(File.join(other_intent_dir, "81--x.md"), "## Intent\nx\n")
    spec_path = File.join(other_intent_dir, "spec.md")

    # The op order matters (spec D3): the first op's code-gate violation must
    # still deny the whole call, but the second op's savepoint-pre ledger line
    # must land anyway, because pass 1 runs savepoint-pre over EVERY op before
    # pass 2 ever checks a deny. A single op-major pass would never reach the
    # second op at all.
    body = patch(update_section(project_file, ["puts 2"]), add_section(spec_path, "content"))
    out, status = run_hook("edit-gates", codex_payload(body))

    assert_equal 2, status.exitstatus, "the first op's code-gate violation must deny the whole call: #{out}"
    ledger = File.read(File.join(other_intent_dir, "savepoint.md"))
    assert_includes ledger, "Why  started"
  end

  def test_lock_gate_deny_reason_uses_the_codex_dollar_prefix
    intent_dir = File.join(@store, "96--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "96--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@root, "INDEX.md"), "## Active\n- [96 - demo](96--demo/96--demo.md)\n\n## Future\n")

    Lock.acquire(intent_dir, session: "other-session")

    plan = File.join(intent_dir, "plan.md")
    body = patch(update_section(plan, ["content"]))
    out, status = run_hook("edit-gates", codex_payload(body, session_id: "me"), session: "me")
    assert_equal 0, status.exitstatus, "lock-gate must never exit non-zero"
    assert_includes out, '"permissionDecision":"deny"'
    assert_includes out, "$plastic-doctor check the lock status"
    refute_includes out, "/plastic-doctor"
  end

  # Pins spec D1 in both directions: a payload with tool_name: "apply_patch"
  # and a payload with a missing tool_name must both run all five gates.
  # Red-phase proof required: swap CodexEditGates::SAVEPOINT_TOOLS/DENY_TOOLS
  # to derive from HookRegistry::GATE_TOOLS instead of CODEX_GATE_TOOLS and
  # confirm this test goes RED (the gate is silently skipped and the write is
  # allowed). This is the single most important red-phase proof in the
  # intent: it is the failure mode where every gate stops firing and nothing
  # else notices.
  def test_every_gate_runs_when_tool_name_is_apply_patch
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, malformed_intent_content))
    payload = codex_payload(body)
    assert_equal "apply_patch", payload["tool_name"]
    out, status = run_hook("edit-gates", payload)
    assert_equal 2, status.exitstatus, "expected create-gate to deny: #{out}"
    assert_includes out, "PLASTIC CREATE GATE"
  end

  def test_every_gate_runs_when_tool_name_is_absent
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, malformed_intent_content))
    payload = codex_payload(body)
    payload.delete("tool_name")
    out, status = run_hook("edit-gates", payload)
    assert_equal 2, status.exitstatus, "expected create-gate to deny: #{out}"
    assert_includes out, "PLASTIC CREATE GATE"
  end

  def test_create_gate_is_add_only_through_the_merged_dispatcher
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    add_body = patch(add_section(intent_path, malformed_intent_content))
    out, status = run_hook("edit-gates", codex_payload(add_body))
    assert_equal 2, status.exitstatus, "an Add of malformed intent content must be denied: #{out}"
    assert_includes out, "PLASTIC CREATE GATE"

    update_body = patch(update_section(intent_path, [malformed_intent_content.chomp]))
    out, status = run_hook("edit-gates", codex_payload(update_body))
    assert_equal 0, status.exitstatus, "the same content as an Update op must be allowed (add-only rule): #{out}"
  end

  def test_an_unparseable_envelope_still_fails_open_through_edit_gates
    out, status = run_hook("edit-gates", codex_payload("not a real patch envelope"))
    assert_equal 0, status.exitstatus
    assert_includes out, "plastic apply_patch parse:"
  end

  def test_a_multi_op_patch_denies_on_the_first_violating_op
    intent_dir = File.join(@store, "52--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "52--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(intent_dir, "spec.md"), "spec\n")
    clean_file = File.join(@root, "code", "clean.rb")
    violating_file = File.join(@root, "code", "bad.rb")
    FileUtils.mkdir_p(File.dirname(clean_file))
    File.write(clean_file, "puts 1\n")
    File.write(violating_file, "puts 1\n")
    silence_stderr { Bridge.arm_auto(nil, intent_id: "52", intent_dir: intent_dir, store: @store, name: "demo") }

    # clean_file always escapes (# plastic-ok), so it never denies on its own
    # in either position; violating_file is the sole source of the deny.
    body_clean_first = patch(update_section(clean_file, ["ok", "# plastic-ok"]), update_section(violating_file, ["bad"]))
    _out, status = run_hook("edit-gates", codex_payload(body_clean_first))
    assert_equal 2, status.exitstatus, "the second op's violation must still deny the whole call"

    body_violating_first = patch(update_section(violating_file, ["bad"]), update_section(clean_file, ["ok", "# plastic-ok"]))
    _out, status = run_hook("edit-gates", codex_payload(body_violating_first))
    assert_equal 2, status.exitstatus, "the first op's violation must deny the whole call"
  end

  # ---- review finding 1 (post-delivery): an unrecognized, non-empty tool_name
  # must not silently skip every gate. Codex only ever invokes this dispatcher
  # from the apply_patch matcher, so the harness has already matched by the
  # time we get here; a future Codex rename (or an adversarial payload) that
  # carries a tool_name CODEX_GATE_TOOLS does not recognize must still run all
  # five gates, loudly (one stderr line naming the unexpected tool), not
  # silently allow. ----

  def test_unexpected_tool_name_still_runs_every_gate
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, malformed_intent_content))
    payload = codex_payload(body)
    payload["tool_name"] = "patch"
    out, status = run_hook("edit-gates", payload)
    assert_equal 2, status.exitstatus, "an unrecognized tool_name must not skip gates: #{out}"
    assert_includes out, "PLASTIC CREATE GATE"
    assert_includes out, "unexpected tool_name"
  end

  def test_recognized_tool_name_emits_no_unexpected_tool_line
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, malformed_intent_content))
    payload = codex_payload(body)
    assert_equal "apply_patch", payload["tool_name"]
    out, status = run_hook("edit-gates", payload)
    assert_equal 2, status.exitstatus, "control: apply_patch must still deny: #{out}"
    refute_includes out, "unexpected tool_name"
  end

  def test_absent_tool_name_emits_no_unexpected_tool_line
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, malformed_intent_content))
    payload = codex_payload(body)
    payload.delete("tool_name")
    out, status = run_hook("edit-gates", payload)
    assert_equal 2, status.exitstatus, "control: an absent tool_name must still deny: #{out}"
    refute_includes out, "unexpected tool_name"
  end

  # ---- review finding 2 (post-delivery): a missing scripts/lib/codex_edit_gates.rb
  # (a future manifest gap, exactly the class of bug the full suite caught
  # during this intent's own delivery) must fail open with a gate decision,
  # never crash. LoadError is a ScriptError, a sibling of StandardError, not a
  # subclass, so the dispatcher's rescue must name both. ----

  def mutated_scripts_dir_missing_codex_edit_gates_lib
    real_scripts = File.expand_path("../scripts", __dir__)
    copy_root = Dir.mktmpdir("codex-hook-missing-lib")
    copy = File.join(copy_root, "scripts")
    FileUtils.cp_r(real_scripts, copy)
    FileUtils.rm_f(File.join(copy, "lib", "codex_edit_gates.rb"))
    copy
  end

  def test_missing_codex_edit_gates_lib_fails_open_not_crash
    copy = mutated_scripts_dir_missing_codex_edit_gates_lib
    script = File.join(copy, "codex-hook")
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, valid_intent_content))
    env = { "PLASTIC_TMP" => @bridge_tmp, "CLAUDE_CODE_SESSION_ID" => nil, "HOME" => @fake_home }
    out = nil
    IO.popen(env, [RbConfig.ruby, script, "edit-gates"], "r+", err: [:child, :out]) do |io|
      io.write(JSON.generate(codex_payload(body)))
      io.close_write
      out = io.read
    end
    assert_equal 0, $?.exitstatus, "a missing lib must fail open, never crash: #{out}"
    assert_includes out, "plastic codex edit-gates error:"
  ensure
    FileUtils.rm_rf(File.dirname(copy)) if copy
  end
end
