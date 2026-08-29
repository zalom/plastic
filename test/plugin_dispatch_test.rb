require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "shellwords"
require "open3"

# Intent 234. hooks/hooks.json and hooks/run-hook are the plugin/marketplace
# entry surface, and scripts/lib/installer_core.rb skips both in the
# direct-install copy loop, so before this file nothing in the suite ever
# resolved a command string out of hooks.json, let alone executed one.
#
# Every command is derived from hooks.json itself (intent 200: never a
# hand-kept list), so a newly added hook is covered here with no test edit.
class PluginDispatchTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  Complaint = Struct.new(:command, :kind, :message)

  # The five Complaint kinds unresolved_commands can produce split into two
  # levels: a command's own argv[0] (target-level) and, only when that argv[0]
  # is run-hook, the launcher named by its second argument (run-hook-level).
  # This is the single source for that split. Test 1 selects it, test 2
  # rejects the same constant, so the partition is total by construction: if a
  # kind is ever added or removed here, coverage does not silently vanish, it
  # moves from one test's catch to the other's. Two independently hand-kept
  # arrays (one per test) previously encoded this split and a dropped entry in
  # either one went unnoticed by the whole suite; this replaces both with one.
  TARGET_LEVEL_KINDS = %i[missing_target not_executable_target].freeze

  def setup
    @tmp = Dir.mktmpdir("plugin-dispatch")
    @plugin_root = File.join(@tmp, "plugin-root")
    FileUtils.mkdir_p(@plugin_root)
    # A plugin install exposes the repo tree at ${CLAUDE_PLUGIN_ROOT}. Every
    # launcher reaches its Ruby sibling through $SCRIPT_DIR/../scripts/, so
    # both directories have to be present for dispatch to work at all.
    FileUtils.cp_r(File.join(REPO, "hooks"), @plugin_root)
    FileUtils.cp_r(File.join(REPO, "scripts"), @plugin_root)
    @home = File.join(@tmp, "home")
    @bridge_tmp = File.join(@tmp, "bridge")
    FileUtils.mkdir_p(@home)
    FileUtils.mkdir_p(@bridge_tmp)

    assert File.executable?(File.join(plugin_hooks_dir, "run-hook")),
           "fixture assumption: the copied run-hook must keep its executable bit"
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def plugin_hooks_dir
    File.join(@plugin_root, "hooks")
  end

  # Never mutate the test process ENV: pass a per-spawn env hash instead, the
  # convention in bash_gate_test.rb and codex_hooks_test.rb.
  def hook_env
    {
      "HOME" => @home,
      "PLASTIC_HOME" => nil,
      "PLASTIC_TMP" => @bridge_tmp,
      "CLAUDE_CODE_SESSION_ID" => nil,
    }
  end

  def hooks_json_commands(root)
    raw = JSON.parse(File.read(File.join(root, "hooks", "hooks.json")))
    raw.fetch("hooks").values.flatten
       .flat_map { |group| group.fetch("hooks") }
       .map { |hook| hook.fetch("command") }
  end

  # The one pure unit under test. Returns a Complaint per unresolvable command.
  # Shellwords.split is the standard-library answer to the shipped command
  # shape, in place of a bespoke regex.
  def unresolved_commands(root)
    hooks_json_commands(root).flat_map do |command|
      argv = Shellwords.split(command.gsub("${CLAUDE_PLUGIN_ROOT}", root))
      target = argv.first
      unless File.file?(target)
        next [Complaint.new(command, :missing_target, "#{command}: #{target} does not exist")]
      end

      found = []
      unless File.executable?(target)
        found << Complaint.new(command, :not_executable_target, "#{command}: #{target} is not executable")
      end
      next found unless File.basename(target) == "run-hook"

      name = argv[1].to_s
      if name.empty?
        found << Complaint.new(command, :missing_name, "#{command}: run-hook was given no hook name")
        next found
      end

      launcher = File.join(File.dirname(target), name)
      if !File.file?(launcher)
        found << Complaint.new(command, :missing_launcher, "#{command}: run-hook target #{name} does not exist")
      elsif !File.executable?(launcher)
        found << Complaint.new(command, :not_executable_launcher, "#{command}: run-hook target #{name} is not executable")
      end
      found
    end
  end

  # A throwaway plugin root carrying a real run-hook plus a hand-written
  # hooks.json, so the checker above can be proven to actually fail.
  def synthetic_plugin_root(events)
    root = Dir.mktmpdir("synthetic", @tmp)
    FileUtils.mkdir_p(File.join(root, "hooks"))
    FileUtils.cp(File.join(REPO, "hooks", "run-hook"), File.join(root, "hooks", "run-hook"))
    FileUtils.chmod(0o755, File.join(root, "hooks", "run-hook"))
    payload = { "hooks" => events.transform_values { |commands|
      [{ "matcher" => "", "hooks" => commands.map { |c| { "type" => "command", "command" => c } } }]
    } }
    File.write(File.join(root, "hooks", "hooks.json"), JSON.pretty_generate(payload))
    root
  end

  def write_launcher(root, name, mode:, body: "#!/bin/bash\nexit 0\n")
    path = File.join(root, "hooks", name)
    File.write(path, body)
    FileUtils.chmod(mode, path)
    path
  end

  # --- AC1 to AC3: the shipped manifest resolves against a simulated plugin root ---

  def test_every_hooks_json_command_resolves_to_an_executable_file
    commands = hooks_json_commands(@plugin_root)
    assert_operator commands.size, :>=, 8,
                    "fixture floor: hooks.json declares at least 8 commands; an empty walk is not a pass"

    bad = unresolved_commands(@plugin_root)
          .select { |c| TARGET_LEVEL_KINDS.include?(c.kind) }
    assert_empty bad.map(&:message)
  end

  def test_every_run_hook_target_resolves_to_an_executable_launcher
    wrapped = hooks_json_commands(@plugin_root).select { |c| c.include?("run-hook") }
    assert_operator wrapped.size, :>=, 7,
                    "fixture floor: at least 7 commands dispatch through run-hook"

    # Everything that is not a target-level complaint is a run-hook-level one
    # by construction (see TARGET_LEVEL_KINDS): missing_name, missing_launcher,
    # and not_executable_launcher all land here with no allow-list of their
    # own to fall out of sync, and any future kind lands here too until it is
    # deliberately added to TARGET_LEVEL_KINDS instead.
    bad = unresolved_commands(@plugin_root)
          .reject { |c| TARGET_LEVEL_KINDS.include?(c.kind) }
    assert_empty bad.map(&:message)
  end

  def test_every_hooks_json_command_uses_the_plugin_root_variable
    commands = hooks_json_commands(REPO)
    assert_operator commands.size, :>=, 8,
                    "fixture floor: hooks.json declares at least 8 commands; an empty walk is not a pass"

    commands.each do |command|
      assert_includes command, "${CLAUDE_PLUGIN_ROOT}/hooks/",
                      "#{command} must address its launcher through the plugin root variable"
      Shellwords.split(command.gsub("${CLAUDE_PLUGIN_ROOT}", "PLUGINROOT")).each do |token|
        refute token.start_with?("/"),
               "#{command} carries an absolute path that would not survive a plugin install"
      end
    end
  end

  # --- AC4 and AC5: the checker is falsifiable and derived, proved in-suite ---

  def test_the_resolution_check_reports_missing_and_non_executable_targets
    root = synthetic_plugin_root(
      "SessionStart" => ['"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook" ghost'],
      "PreCompact" => ['"${CLAUDE_PLUGIN_ROOT}/hooks/limp"'],
      # run-hook dispatched to a present-but-0644 launcher: the founding defect's
      # exact shape (hooks/create-gate shipped 100644). Proves not_executable_launcher
      # is actually reachable, not merely a dead branch.
      "PostToolUse" => ['"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook" limp'],
      # run-hook given no hook name at all. Proves missing_name is reachable too.
      "Notification" => ['"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook"'],
    )
    write_launcher(root, "limp", mode: 0o644)

    kinds = unresolved_commands(root).map(&:kind).sort_by(&:to_s)
    assert_equal %i[missing_launcher missing_name not_executable_launcher not_executable_target], kinds
  end

  def test_a_new_hooks_json_entry_is_checked_without_editing_this_test
    root = synthetic_plugin_root(
      "UserPromptSubmit" => ['"${CLAUDE_PLUGIN_ROOT}/hooks/brand-new-hook"'],
    )

    complaints = unresolved_commands(root)
    assert_equal [:missing_target], complaints.map(&:kind)
    assert_includes complaints.first.message, "brand-new-hook"
  end

  # --- AC6 to AC8: run-hook's dispatch contract, driven as a real subprocess ---

  PROBE_BODY = <<~SH
    #!/bin/bash
    echo "PROBE-OK $*"
    cat
    exit 7
  SH

  def test_run_hook_forwards_argv_stdin_and_exit_code
    write_launcher(@plugin_root, "probe", mode: 0o755, body: PROBE_BODY)
    payload = JSON.generate("session_id" => "sess-234", "user_prompt" => "smoke")

    out, err, status = Open3.capture3(hook_env, File.join(plugin_hooks_dir, "run-hook"),
                                      "probe", "--flag", stdin_data: payload)

    # 7 is deliberately none of 0, 1, or 2: a gate DENY exits 2, so this proves
    # a real gate verdict reaches the harness through the plugin path.
    assert_equal 7, status.exitstatus, "run-hook must propagate the launcher's exit status"
    assert_includes out, "PROBE-OK --flag", "run-hook must shift the name and forward the rest of argv"
    assert_includes out, payload, "run-hook must forward stdin untouched"
    assert_empty err
  end

  def test_run_hook_exits_126_on_a_present_but_non_executable_launcher
    write_launcher(@plugin_root, "limp", mode: 0o644)

    _out, err, status = Open3.capture3(hook_env, File.join(plugin_hooks_dir, "run-hook"),
                                       "limp", stdin_data: "{}")

    # POSIX 126 is "found but not executable". This is the exact signature
    # hooks/create-gate shipped with for its whole life, the defect this intent
    # was born from, reproduced mechanically for the first time.
    assert_equal 126, status.exitstatus
    assert_match(/[Pp]ermission denied/, err)
  end

  # run-hook tests -f, not -x, and falls off the end when the named launcher is
  # absent: no output, exit 0. Pinned deliberately, not tolerated by accident.
  # Intent 111: a guard must fail milder than the bug it guards, and run-hook
  # runs inside live PreToolUse where a hard failure would block the user's tool
  # call. The hole is closed at test time by
  # test_every_run_hook_target_resolves_to_an_executable_launcher, not at runtime.
  # Changing this behavior means deliberately rewriting this test first.
  def test_run_hook_is_silent_and_exit_zero_on_a_missing_launcher
    out, err, status = Open3.capture3(hook_env, File.join(plugin_hooks_dir, "run-hook"),
                                      "no-such-hook", stdin_data: "{}")

    assert_equal 0, status.exitstatus
    assert_empty out
    assert_empty err
  end

  # --- AC9: one real launcher, end to end, with real stdin JSON ---

  # hooks/capture's bash body pipes stdin straight to scripts/hook-capture with
  # no bash-side fallback (intent 298 collapsed continue/future-intent-check/
  # auto-arm into this one launcher), so a bare hookEventName assertion here
  # is already proof the Ruby path ran.
  def test_the_capture_launcher_runs_end_to_end_through_run_hook
    FileUtils.mkdir_p(File.join(@home, ".plastic", "store"))
    File.write(File.join(@home, ".plastic", "INDEX.md"), "# Intent Index\n\n## Active\n\n## Future\n")
    payload = JSON.generate("session_id" => "sess-234", "user_prompt" => "continue")

    out, _err, status = Open3.capture3(hook_env, File.join(plugin_hooks_dir, "run-hook"),
                                       "capture", stdin_data: payload)

    assert_equal 0, status.exitstatus
    refute_empty out.strip, "the capture launcher must emit context on a continue prompt"
    parsed = JSON.parse(out)
    assert_equal "UserPromptSubmit", parsed.dig("hookSpecificOutput", "hookEventName")
  end
end
