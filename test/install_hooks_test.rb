require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"
require "stringio"

require_relative "../scripts/lib/installer_core"
require_relative "../scripts/lib/hook_registry"

PLASTIC_TEST_HOME = File.join(Dir.tmpdir, "plastic-test-home-#{Process.pid}")

class MergeClaudeHooksTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("hooks-test")
    @settings_path = File.join(@dir, "settings.json")
    @installer = InstallerCore.new(
      package_root: "/tmp/plastic-test-pkg",
      plastic_home: PLASTIC_TEST_HOME,
      version: "1.0.0-test",
    )
    FileUtils.rm_rf(PLASTIC_TEST_HOME)
    FileUtils.mkdir_p(PLASTIC_TEST_HOME)
  end

  def teardown
    FileUtils.rm_rf(@dir)
    FileUtils.rm_rf(PLASTIC_TEST_HOME)
  end

  def tty_input(str)
    io = StringIO.new(str)
    def io.tty?
      true
    end
    io
  end

  def test_merge_into_empty_settings
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    hooks = settings["hooks"]

    assert hooks["SessionStart"], "SessionStart hook group should exist"
    group = hooks["SessionStart"].first
    assert_equal "", group["matcher"]
    commands = group["hooks"].map { |h| h["command"] }
    assert commands.any? { |c| c.include?("plastic-session-start") }
    assert commands.none? { |c| c.include?("ruby ") }, "No ruby prefix should be present"

    assert settings["statusLine"], "statusLine should be set"
    assert settings["statusLine"]["command"].include?("plastic-statusline")
  end

  def test_purge_stale_rb_entries
    stale_settings = {
      "hooks" => {
        "SessionStart" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "ruby /Users/test/.claude/hooks/plastic-session-start.rb" },
              { "type" => "command", "command" => "ruby /Users/test/.claude/hooks/plastic-session-start" },
              { "type" => "command", "command" => "serena-hooks activate --client=claude-code" },
            ],
          },
        ],
        "UserPromptSubmit" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "ruby /Users/test/.claude/hooks/plastic-continue.rb" },
            ],
          },
        ],
      },
    }

    File.write(@settings_path, JSON.pretty_generate(stale_settings))
    @installer.merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))

    all_commands = settings["hooks"].flat_map do |_, groups|
      groups.flat_map { |g| (g["hooks"] || []).map { |h| h["command"] } }
    end

    assert all_commands.none? { |c| c.include?(".rb") }, "All .rb entries should be purged: #{all_commands.inspect}"
    assert all_commands.none? { |c| c.start_with?("ruby ") }, "All ruby-prefixed entries should be purged: #{all_commands.inspect}"
    assert all_commands.any? { |c| c.include?("serena-hooks") }, "Non-plastic hooks should be preserved"
  end

  def test_merge_preserves_non_plastic_hooks
    existing = {
      "hooks" => {
        "SessionStart" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "serena-hooks activate --client=claude-code" },
            ],
          },
        ],
        "PreToolUse" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "serena-hooks remind --client=claude-code" },
            ],
          },
        ],
      },
    }

    File.write(@settings_path, JSON.pretty_generate(existing))
    @installer.merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))

    serena_group = settings["hooks"]["SessionStart"].find { |g| g["hooks"].any? { |h| h["command"].include?("serena") } }
    assert serena_group, "Serena SessionStart hooks should be preserved"

    assert settings["hooks"]["PreToolUse"], "PreToolUse hooks should be preserved"
  end

  def test_update_replaces_existing_plastic_group
    first_run = {
      "hooks" => {
        "SessionStart" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "/old/path/plastic-session-start" },
            ],
          },
        ],
      },
    }

    File.write(@settings_path, JSON.pretty_generate(first_run))
    @installer.merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    plastic_group = settings["hooks"]["SessionStart"].find { |g| g["hooks"].any? { |h| h["command"].include?("plastic-") } }

    assert plastic_group, "Plastic group should exist"
    assert_equal 2, plastic_group["hooks"].size, "Should have session-start + check-update"
    assert plastic_group["hooks"].none? { |h| h["command"].include?("/old/path/") }, "Old path should be replaced"
  end

  def test_remove_claude_hooks
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)

    @installer.remove_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))

    assert_nil settings["hooks"], "All plastic hooks should be removed"
    assert_nil settings["statusLine"], "statusLine should be removed"
  end

  # Intent 275, the exact 32b regression: a user-owned SessionStart hook named
  # ~/.claude/hooks/plastic-writing-style is NOT a registry launcher, so it must
  # survive the purge. Written and run FIRST against the unmodified substring
  # predicate to prove the bug (see checklist.md Task 6b).
  def test_user_hook_with_plastic_prefix_survives_merge
    existing = {
      "hooks" => {
        "SessionStart" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "~/.claude/hooks/plastic-writing-style" },
            ],
          },
        ],
      },
    }

    File.write(@settings_path, JSON.pretty_generate(existing))
    @installer.merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    all_commands = settings["hooks"].flat_map do |_, groups|
      groups.flat_map { |g| (g["hooks"] || []).map { |h| h["command"] } }
    end

    assert all_commands.any? { |c| c.include?("plastic-writing-style") },
           "A user hook merely sharing the plastic- prefix must survive the merge: #{all_commands.inspect}"
  end

  def test_user_hook_with_plastic_prefix_survives_in_rb_form
    existing = {
      "hooks" => {
        "SessionStart" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "ruby /Users/test/.claude/hooks/plastic-writing-style.rb" },
            ],
          },
        ],
      },
    }

    File.write(@settings_path, JSON.pretty_generate(existing))
    @installer.merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    all_commands = settings["hooks"].flat_map do |_, groups|
      groups.flat_map { |g| (g["hooks"] || []).map { |h| h["command"] } }
    end

    assert all_commands.any? { |c| c.include?("plastic-writing-style.rb") },
           "The .rb-suffixed form of the user hook must also survive: #{all_commands.inspect}"
  end

  # The line-1231 second-order bug: before the fix, a user plastic-prefixed
  # hook sitting in a group whose matcher equals Plastic's own made `existing`
  # truthy via the substring test, and existing["hooks"] = g["hooks"]
  # OVERWROTE the user's hook with Plastic's SessionStart group. After the
  # fix, the user hook survives in its own group AND Plastic's group is
  # registered alongside it.
  def test_user_plastic_prefixed_hook_in_matching_group_is_not_clobbered
    existing = {
      "hooks" => {
        "SessionStart" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "~/.claude/hooks/plastic-writing-style" },
            ],
          },
        ],
      },
    }

    File.write(@settings_path, JSON.pretty_generate(existing))
    @installer.merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    session_start_commands = settings["hooks"]["SessionStart"].flat_map { |g| (g["hooks"] || []).map { |h| h["command"] } }

    assert session_start_commands.any? { |c| c.include?("plastic-writing-style") },
           "The user hook must survive: #{session_start_commands.inspect}"
    assert session_start_commands.any? { |c| c.include?("plastic-session-start") },
           "Plastic's own SessionStart group must still be registered alongside it: #{session_start_commands.inspect}"
  end

  def test_retired_launcher_entry_is_purged
    existing = {
      "hooks" => {
        "SessionStart" => [
          {
            "matcher" => "",
            "hooks" => [
              { "type" => "command", "command" => "~/.claude/hooks/plastic-lock-gate" },
            ],
          },
        ],
      },
    }

    File.write(@settings_path, JSON.pretty_generate(existing))
    @installer.merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    all_commands = settings["hooks"].flat_map do |_, groups|
      groups.flat_map { |g| (g["hooks"] || []).map { |h| h["command"] } }
    end

    assert all_commands.none? { |c| c.include?("plastic-lock-gate") },
           "A retired launcher entry must be purged: #{all_commands.inspect}"
  end

  def test_merge_prints_every_removed_entry
    existing = {
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "~/.claude/hooks/plastic-lock-gate" }] },
        ],
        "UserPromptSubmit" => [
          { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "~/.claude/hooks/plastic-code-gate" }] },
        ],
      },
    }
    File.write(@settings_path, JSON.pretty_generate(existing))

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.merge_claude_hooks(@settings_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    assert_includes output, "plastic-lock-gate"
    assert_includes output, "plastic-code-gate"
  end

  def test_merge_prints_reserved_prefix_notice_for_kept_hooks
    existing = {
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "~/.claude/hooks/plastic-writing-style" }] },
        ],
      },
    }
    File.write(@settings_path, JSON.pretty_generate(existing))

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.merge_claude_hooks(@settings_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    assert_includes output, "plastic-writing-style"
    assert_match(/reserved/i, output)
    assert_match(/prefix/i, output)
  end

  def test_merge_prints_nothing_when_nothing_removed
    File.write(@settings_path, "{}")

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.merge_claude_hooks(@settings_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    refute_match(/Removed/, output)
  end

  def test_remove_claude_hooks_keeps_user_plastic_prefixed_hook
    existing = {
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [
            { "type" => "command", "command" => "~/.claude/hooks/plastic-writing-style" },
            { "type" => "command", "command" => "~/.claude/hooks/plastic-session-start" },
          ] },
        ],
      },
    }
    File.write(@settings_path, JSON.pretty_generate(existing))
    @installer.remove_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    remaining = settings.dig("hooks", "SessionStart")&.flat_map { |g| (g["hooks"] || []).map { |h| h["command"] } } || []

    assert remaining.any? { |c| c.include?("plastic-writing-style") }, "User hook must survive: #{remaining.inspect}"
    assert remaining.none? { |c| c.include?("plastic-session-start") }, "Plastic's own hook must be removed: #{remaining.inspect}"
  end

  def test_retired_launchers_are_disjoint_from_current
    overlap = HookRegistry.claude_launcher_names & HookRegistry::RETIRED_CLAUDE_LAUNCHERS
    assert_empty overlap, "Retired launchers must never overlap current ones: #{overlap.inspect}"
  end

  def test_claude_purge_predicate_truth_table
    assert HookRegistry.claude_purge_command?("/Users/x/.claude/hooks/plastic-session-start")
    assert HookRegistry.claude_purge_command?("ruby /Users/x/.claude/hooks/plastic-session-start.rb")
    assert HookRegistry.claude_purge_command?("/Users/x/.claude/hooks/plastic-lock-gate")
    assert HookRegistry.claude_purge_command?("/Users/x/.claude/hooks/plastic-statusline")

    refute HookRegistry.claude_purge_command?("~/.claude/hooks/plastic-writing-style")
    refute HookRegistry.claude_purge_command?("ruby ~/.claude/hooks/plastic-writing-style.rb")
    refute HookRegistry.claude_purge_command?("serena-hooks activate --client=claude-code")
  end

  # Drift pin: every command claude_settings_hooks builds must be matched by
  # claude_purge_command?, or a re-merge would stop being idempotent (a fresh
  # registration would never be recognised as ours on the next purge pass).
  def test_every_registered_claude_command_is_purgeable
    commands = HookRegistry.claude_settings_hooks(hook_dir: "/tmp/h").values.flatten.flat_map do |g|
      g["hooks"].map { |h| h["command"] }
    end
    refute_empty commands
    commands.each do |cmd|
      assert HookRegistry.claude_purge_command?(cmd), "#{cmd} must be purgeable"
    end
  end

  def test_hook_scripts_rewrite_relative_paths
    # Simulate a hook source file with the relative $SCRIPT_DIR/../scripts/ path
    pkg_root = Dir.mktmpdir("plastic-pkg")
    hooks_src = File.join(pkg_root, "hooks")
    FileUtils.mkdir_p(hooks_src)

    File.write(File.join(hooks_src, "session-start"), <<~SH)
      #!/bin/bash
      SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
      ruby "$SCRIPT_DIR/../scripts/hook-session-start" "$@"
    SH

    File.write(File.join(hooks_src, "hooks.json"), "{}")
    File.write(File.join(hooks_src, "run-hook"), "#!/bin/bash")

    hooks_dest = File.join(@dir, "hooks")
    FileUtils.mkdir_p(hooks_dest)

    # Replicate the installer's copy-and-rewrite logic
    Dir.glob(File.join(hooks_src, "*")).each do |f|
      next unless File.file?(f)
      basename = File.basename(f)
      next if %w[hooks.json run-hook].include?(basename)
      dest_name = basename.start_with?("plastic-") ? basename : "plastic-#{basename}"
      dest = File.join(hooks_dest, dest_name)
      content = File.read(f)
      content = content.gsub('$SCRIPT_DIR/../scripts/', '$HOME/.plastic/scripts/')
      File.write(dest, content)
    end

    installed_hook = File.read(File.join(hooks_dest, "plastic-session-start"))
    assert_includes installed_hook, '$HOME/.plastic/scripts/hook-session-start',
      "Installed hook should reference $HOME/.plastic/scripts/"
    refute_includes installed_hook, '$SCRIPT_DIR/../scripts/',
      "Installed hook should NOT contain relative $SCRIPT_DIR/../scripts/ path"
  ensure
    FileUtils.rm_rf(pkg_root)
  end

  def test_remove_preserves_non_plastic
    mixed = {
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "serena-hooks activate" }] },
          { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "/path/plastic-session-start" }] },
        ],
      },
      "statusLine" => { "type" => "command", "command" => "/path/plastic-statusline" },
    }

    File.write(@settings_path, JSON.pretty_generate(mixed))
    @installer.remove_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    assert_equal 1, settings["hooks"]["SessionStart"].size, "Only serena group should remain"
    assert_nil settings["statusLine"], "Plastic statusLine should be removed"
  end

  def test_merge_saves_original_statusline
    original = { "type" => "command", "command" => "/Users/test/.claude/statusline.rb" }
    File.write(@settings_path, JSON.pretty_generate({ "statusLine" => original }))

    @installer.merge_claude_hooks(@settings_path)

    backup_path = File.join(PLASTIC_TEST_HOME, ".cache", "original-statusline.json")
    assert File.exist?(backup_path), "Original statusline should be backed up"

    saved = JSON.parse(File.read(backup_path))
    assert_equal "/Users/test/.claude/statusline.rb", saved["command"]

    settings = JSON.parse(File.read(@settings_path))
    assert settings["statusLine"]["command"].include?("plastic-statusline"), "statusLine should now point to plastic"
  end

  def test_merge_does_not_overwrite_backup_on_update
    cache_dir = File.join(PLASTIC_TEST_HOME, ".cache")
    FileUtils.mkdir_p(cache_dir)
    backup_path = File.join(cache_dir, "original-statusline.json")
    File.write(backup_path, JSON.pretty_generate({ "type" => "command", "command" => "/original/statusline.rb" }))

    File.write(@settings_path, JSON.pretty_generate({
      "statusLine" => { "type" => "command", "command" => "/old/plastic-statusline" },
    }))

    @installer.merge_claude_hooks(@settings_path)

    saved = JSON.parse(File.read(backup_path))
    assert_equal "/original/statusline.rb", saved["command"], "Backup should not be overwritten during update"
  end

  def test_remove_restores_original_statusline
    cache_dir = File.join(PLASTIC_TEST_HOME, ".cache")
    FileUtils.mkdir_p(cache_dir)
    File.write(File.join(cache_dir, "original-statusline.json"),
      JSON.pretty_generate({ "type" => "command", "command" => "/Users/test/.claude/statusline.rb" }))

    File.write(@settings_path, JSON.pretty_generate({
      "hooks" => {},
      "statusLine" => { "type" => "command", "command" => "/path/plastic-statusline" },
    }))

    @installer.remove_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    assert_equal "/Users/test/.claude/statusline.rb", settings.dig("statusLine", "command"),
      "Original statusline should be restored on uninstall"
  end

  def test_remove_prints_every_removed_entry
    mixed = {
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "serena-hooks activate" }] },
          { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "/path/plastic-session-start" }] },
        ],
      },
      "statusLine" => { "type" => "command", "command" => "/path/plastic-statusline" },
    }
    File.write(@settings_path, JSON.pretty_generate(mixed))

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.remove_claude_hooks(@settings_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    assert_includes output, "plastic-session-start"
    assert_includes output, "SessionStart"
    assert_match(/Removed 1 Plastic hook entry from settings\.json/, output)
    refute_match(/stale/i, output)
    refute_includes output, "serena-hooks"
  end

  def test_remove_prints_nothing_when_nothing_removed
    existing = {
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "serena-hooks activate" }] },
        ],
      },
    }
    File.write(@settings_path, JSON.pretty_generate(existing))

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.remove_claude_hooks(@settings_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    refute_match(/Removed/, output)
  end

  def test_remove_prints_statusline_restore
    cache_dir = File.join(PLASTIC_TEST_HOME, ".cache")
    FileUtils.mkdir_p(cache_dir)
    File.write(File.join(cache_dir, "original-statusline.json"),
      JSON.pretty_generate({ "type" => "command", "command" => "/Users/test/.claude/statusline.rb" }))

    File.write(@settings_path, JSON.pretty_generate({
      "hooks" => {},
      "statusLine" => { "type" => "command", "command" => "/path/plastic-statusline" },
    }))

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.remove_claude_hooks(@settings_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    assert_match(/statusLine/i, output)
    assert_includes output, "/Users/test/.claude/statusline.rb"
    assert_match(/restored/i, output)
  end

  # F1 regression: a corrupted original-statusline.json cache (an Array or a bare
  # number instead of the Hash merge always wrote) must not crash remove_claude_hooks.
  # Crashing here is worse than main: uninstall_agent already deleted the launcher
  # files by the time remove_claude_hooks runs, so a raised TypeError would leave
  # every Plastic hook still registered in settings.json with no launchers left to
  # run them.
  def test_remove_survives_array_shaped_statusline_cache
    cache_dir = File.join(PLASTIC_TEST_HOME, ".cache")
    FileUtils.mkdir_p(cache_dir)
    File.write(File.join(cache_dir, "original-statusline.json"), JSON.generate([1, 2]))

    File.write(@settings_path, JSON.pretty_generate({
      "hooks" => {},
      "statusLine" => { "type" => "command", "command" => "/path/plastic-statusline" },
    }))

    @installer.remove_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    refute settings.key?("statusLine"), "A malformed cache must not be restored as statusLine"
  end

  def test_remove_survives_numeric_shaped_statusline_cache
    cache_dir = File.join(PLASTIC_TEST_HOME, ".cache")
    FileUtils.mkdir_p(cache_dir)
    File.write(File.join(cache_dir, "original-statusline.json"), JSON.generate(5))

    File.write(@settings_path, JSON.pretty_generate({
      "hooks" => {},
      "statusLine" => { "type" => "command", "command" => "/path/plastic-statusline" },
    }))

    @installer.remove_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    refute settings.key?("statusLine"), "A malformed cache must not be restored as statusLine"
  end

  def test_remove_does_not_print_kept_user_hook
    existing = {
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [
            { "type" => "command", "command" => "~/.claude/hooks/plastic-writing-style" },
            { "type" => "command", "command" => "~/.claude/hooks/plastic-session-start" },
          ] },
        ],
      },
    }
    File.write(@settings_path, JSON.pretty_generate(existing))

    original_stdout = $stdout
    output = nil
    begin
      $stdout = StringIO.new
      @installer.remove_claude_hooks(@settings_path)
      output = $stdout.string
    ensure
      $stdout = original_stdout
    end

    refute_includes output, "plastic-writing-style"
    assert_includes output, "plastic-session-start"
  end

  def test_merge_no_backup_when_no_existing_statusline
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)

    backup_path = File.join(PLASTIC_TEST_HOME, ".cache", "original-statusline.json")
    refute File.exist?(backup_path), "No backup should be created when there was no existing statusline"
  end

  def posttooluse_commands(settings)
    settings["hooks"]["PostToolUse"].flat_map { |g| (g["hooks"] || []).map { |h| h["command"] } }
  end

  def plastic_commands(settings, event)
    Array(settings["hooks"][event]).flat_map { |g| (g["hooks"] || []).map { |h| h["command"].to_s } }
                                  .select { |c| c.include?("plastic-") }
  end

  def merged_settings
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)
    JSON.parse(File.read(@settings_path))
  end

  # Intent 309: power-tools is retired. UserPromptSubmit registers capture only, and an
  # old plastic-power-tools entry is purged on merge.
  def test_user_prompt_submit_registers_capture_only_and_purges_power_tools
    existing = { "hooks" => { "UserPromptSubmit" => [
      { "matcher" => "", "hooks" => [
        { "type" => "command", "command" => "~/.claude/hooks/plastic-power-tools" },
      ] },
    ] } }
    File.write(@settings_path, JSON.pretty_generate(existing))
    @installer.merge_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))
    commands = Array(settings["hooks"]["UserPromptSubmit"]).flat_map { |g| g["hooks"].map { |h| h["command"] } }
    assert commands.any? { |c| c.end_with?("plastic-capture") }, commands.inspect
    refute commands.any? { |c| c.include?("plastic-power-tools") },
           "the retired power-tools entry must be purged: #{commands.inspect}"
  end

  def test_statusline_no_existing_line_installs_plastic_silently
    File.write(@settings_path, "{}")
    choice = @installer.statusline_choice(@settings_path)
    assert_equal :plastic, choice

    @installer.merge_claude_hooks(@settings_path, choice: choice)
    settings = JSON.parse(File.read(@settings_path))
    assert settings["statusLine"]["command"].include?("plastic-statusline")
  end

  def test_statusline_existing_nonplastic_tty_keep
    original = { "type" => "command", "command" => "/Users/test/.claude/statusline.rb" }
    File.write(@settings_path, JSON.pretty_generate({ "statusLine" => original }))

    choice = @installer.statusline_choice(@settings_path, input: tty_input("1\n"))
    assert_equal :keep, choice

    @installer.merge_claude_hooks(@settings_path, choice: choice)
    settings = JSON.parse(File.read(@settings_path))
    assert_equal "/Users/test/.claude/statusline.rb", settings.dig("statusLine", "command"),
      "Kept statusline should be untouched"

    backup_path = File.join(PLASTIC_TEST_HOME, ".cache", "original-statusline.json")
    assert File.exist?(backup_path), "Original statusline should still be backed up"
  end

  def test_statusline_existing_nonplastic_tty_switch
    original = { "type" => "command", "command" => "/Users/test/.claude/statusline.rb" }
    File.write(@settings_path, JSON.pretty_generate({ "statusLine" => original }))

    choice = @installer.statusline_choice(@settings_path, input: tty_input("2\n"))
    assert_equal :plastic, choice

    @installer.merge_claude_hooks(@settings_path, choice: choice)
    settings = JSON.parse(File.read(@settings_path))
    assert settings["statusLine"]["command"].include?("plastic-statusline")

    backup_path = File.join(PLASTIC_TEST_HOME, ".cache", "original-statusline.json")
    assert File.exist?(backup_path), "Original statusline should be backed up"
  end

  def test_statusline_existing_nonplastic_non_tty_defaults_keep
    original = { "type" => "command", "command" => "/Users/test/.claude/statusline.rb" }
    File.write(@settings_path, JSON.pretty_generate({ "statusLine" => original }))

    non_tty = StringIO.new("")
    choice = @installer.statusline_choice(@settings_path, input: non_tty)
    assert_equal :keep, choice
  end

  def test_statusline_flag_keep_and_plastic_deterministic
    original = { "type" => "command", "command" => "/Users/test/.claude/statusline.rb" }
    File.write(@settings_path, JSON.pretty_generate({ "statusLine" => original }))

    keep_choice = @installer.statusline_choice(@settings_path, argv: ["--statusline", "keep"], input: tty_input("2\n"))
    assert_equal :keep, keep_choice

    plastic_choice = @installer.statusline_choice(@settings_path, argv: ["--statusline", "plastic"], input: tty_input("1\n"))
    assert_equal :plastic, plastic_choice
  end

  def test_statusline_existing_plastic_reinstall_no_prompt
    File.write(@settings_path, JSON.pretty_generate({
      "statusLine" => { "type" => "command", "command" => "/path/plastic-statusline" },
    }))

    choice = @installer.statusline_choice(@settings_path, input: tty_input("1\n"), reinstall: true)
    assert_equal :plastic, choice, "an already-plastic line must stay plastic without consuming the prompt"
  end

  REPO = File.expand_path("../../", __FILE__)

  # Intent 244 / verdict row 13: hooks/create-gate shipped 100644 and exited 126
  # on a marketplace install for its whole life, invisible to every test. Pin the
  # committed mode of every launcher so a new one cannot repeat it.
  def test_every_committed_hook_launcher_is_executable
    listing = `git -C #{REPO} ls-files -s hooks/`
    entries = listing.lines.map { |l| [l.split("\t").last.strip, l[0, 6]] }
    refute_empty entries, "git ls-files returned nothing; fixture assumption broken"
    entries.each do |path, mode|
      next if File.basename(path) == "hooks.json"
      assert_equal "100755", mode, "#{path} must be committed executable"
    end
  end

  # Intent 244, AC12 second half: the installer's copy loop must leave every
  # installed hook launcher at 0755, independent of the committed mode (the
  # loop chmods explicitly, so this also guards against that chmod regressing).
  def test_installed_hook_launchers_are_all_0755
    installer = InstallerCore.new(package_root: REPO, plastic_home: PLASTIC_TEST_HOME, version: "1.0.0-test")
    claude_dir = File.join(@dir, "claude-install")
    FileUtils.mkdir_p(claude_dir)
    installer.install_claude({ name: "Claude Code", dir: claude_dir }, false)

    hooks_dir = File.join(claude_dir, "hooks")
    installed = Dir.glob(File.join(hooks_dir, "plastic-*"))
    refute_empty installed, "fixture assumption: install_claude must populate #{hooks_dir}"
    installed.each do |dest|
      assert_equal "755", format("%o", File.stat(dest).mode & 0o777), "#{dest} must install at 0755"
    end
  end
  # Intent 302: the edit-path gates are gone, so a fresh merge registers NO
  # PreToolUse group at all.
  def test_merge_registers_no_pretooluse_group
    settings = merged_settings
    assert_empty plastic_commands(settings, "PreToolUse"), "no Plastic PreToolUse hook may ship"
  end

  # The one write-path hook is record, under PostToolUse, on the full WRITE_MATCHER
  # (NotebookEdit and the six Serena edit tools included; the narrower savepoint-pre
  # coverage left with the gates, spec D3 and review B5).
  def test_merge_registers_record_as_the_sole_write_matcher_hook
    settings = merged_settings
    commands = posttooluse_commands(settings)
    assert commands.any? { |c| c.include?("plastic-record") }, "record must be registered"

    groups = settings["hooks"]["PostToolUse"].select { |g| g["matcher"] == HookRegistry::WRITE_MATCHER }
    assert_equal 1, groups.size, "exactly ONE write-matcher group (no matcher collision)"
    assert_equal 1, groups.first["hooks"].size, "exactly one hook in the write group"
    assert_includes groups.first["matcher"], "mcp__serena__replace_content"
    assert_includes groups.first["matcher"], "NotebookEdit"
  end

  def test_posttooluse_carries_exactly_the_registry_groups_across_two_merges
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)
    @installer.merge_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))

    plastic_groups = settings["hooks"]["PostToolUse"].select do |g|
      g["hooks"].any? { |h| h["command"].to_s.include?("plastic-") }
    end
    assert_equal HookRegistry.events["PostToolUse"].size, plastic_groups.size
    assert_equal 1, posttooluse_commands(settings).count { |c| c.include?("plastic-record") },
                 "record must not duplicate across merges"
  end

  # An install that predates intent 302 still carries the merged edit-gates
  # dispatcher and bash-gate under PreToolUse. The purge must remove both and
  # register nothing in their place.
  def test_merge_purges_the_retired_pretooluse_registrations
    settings = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => HookRegistry::WRITE_MATCHER,
            "hooks" => [{ "type" => "command", "command" => "~/.claude/hooks/plastic-edit-gates" }] },
          { "matcher" => "Bash",
            "hooks" => [{ "type" => "command", "command" => "~/.claude/hooks/plastic-bash-gate" }] },
        ],
      },
    }
    File.write(@settings_path, JSON.pretty_generate(settings))
    @installer.merge_claude_hooks(@settings_path)
    merged = JSON.parse(File.read(@settings_path))
    assert_empty plastic_commands(merged, "PreToolUse"),
                 "retired PreToolUse gates must be purged: #{merged["hooks"]["PreToolUse"].inspect}"
  end
end
