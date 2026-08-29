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
# tool_input.command carries a hand-built apply_patch V4A envelope. Since intent
# 302 the dispatcher carries no PreToolUse gate: the apply_patch path serves only
# the PostToolUse record hook, and the live-state hooks relay their launchers. No
# live Codex anywhere (Decision 14): every fixture is hand-built to the guide's
# documented shapes.
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
    assert_includes ctx, "plastic-intent-continuing skill workflow"
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
    _out, status = run_hook("record", { "session_id" => "" })
    assert_equal 0, status.exitstatus
  end

  def test_missing_session_id_fails_open
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, valid_intent_content))
    payload = codex_payload(body)
    payload.delete("session_id")
    _out, status = run_hook("record", payload)
    assert_equal 0, status.exitstatus
  end

  def test_empty_command_fails_open
    _out, status = run_hook("record", codex_payload(""))
    assert_equal 0, status.exitstatus
  end

  def test_non_apply_patch_command_fails_open
    _out, status = run_hook("record", codex_payload("rm -rf /"))
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
    IO.popen(env, [RbConfig.ruby, SCRIPT, "record"], "r+", err: [:child, :out]) do |io|
      io.close_write
      out = io.read
    end
    assert_equal 0, $?.exitstatus, out
  end

  # Intent 302: the PreToolUse gate names are retired. A Codex install that still
  # carries an old `edit-gates` or `bash-gate` entry must fall through to the
  # fail-open else: exit 0, no output, no decision.
  def test_retired_pretooluse_gate_names_fall_through_silently
    intent_path = File.join(@store, "1--demo", "1--demo.md")
    body = patch(add_section(intent_path, malformed_intent_content))
    %w[edit-gates bash-gate].each do |name|
      out, status = run_hook(name, codex_payload(body))
      assert_equal 0, status.exitstatus, "#{name}: #{out}"
      assert_empty out.to_s.strip, "#{name} must print nothing"
    end
  end
end
