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
              { "type" => "command", "command" => "ruby /Users/test/.claude/hooks/plastic-user-prompt.rb" },
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

  def test_merge_no_backup_when_no_existing_statusline
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)

    backup_path = File.join(PLASTIC_TEST_HOME, ".cache", "original-statusline.json")
    refute File.exist?(backup_path), "No backup should be created when there was no existing statusline"
  end

  def pretooluse_commands(settings)
    settings["hooks"]["PreToolUse"].flat_map { |g| (g["hooks"] || []).map { |h| h["command"] } }
  end

  def merged_settings
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)
    JSON.parse(File.read(@settings_path))
  end

  def test_pretooluse_has_both_code_gate_and_create_gate
    settings = merged_settings

    commands = pretooluse_commands(settings)
    assert commands.any? { |c| c.include?("plastic-code-gate") }, "code-gate must be registered"
    assert commands.any? { |c| c.include?("plastic-create-gate") }, "create-gate must be registered"

    code_group = settings["hooks"]["PreToolUse"].find { |g| g["hooks"].any? { |h| h["command"].include?("plastic-code-gate") } }
    create_group = settings["hooks"]["PreToolUse"].find { |g| g["hooks"].any? { |h| h["command"].include?("plastic-create-gate") } }
    assert_equal HookRegistry::WRITE_MATCHER, code_group["matcher"]
    assert_equal HookRegistry::CREATE_MATCHER, create_group["matcher"]
  end

  # Intent 108, D7: the merge consumes HookRegistry, so the two hooks that the
  # old hand-rolled literal dropped (bash-gate shipped dead) are now wired.
  def test_merge_registers_bash_gate_and_savepoint_pre
    settings = merged_settings
    cmds = pretooluse_commands(settings)
    assert cmds.any? { |c| c.include?("plastic-bash-gate") }, "bash-gate must ship wired (D7)"
    assert cmds.any? { |c| c.include?("plastic-savepoint-pre") }
  end

  def test_merge_write_matcher_includes_mcp_edit_tools
    settings = merged_settings
    gate_group = settings["hooks"]["PreToolUse"].find do |g|
      g["hooks"].any? { |h| h["command"].include?("plastic-code-gate") }
    end
    assert_includes gate_group["matcher"], "mcp__serena__replace_content"
  end

  # The whole PreToolUse list carries exactly the registry's groups, and merging
  # twice never duplicates one. Gate-agnostic on purpose: it is derived from
  # HookRegistry.events, so it keeps holding as gates are added, removed, or
  # merged (intent 226, spec D6; it previously lived inside a retrieval-gate test).
  def test_pretooluse_carries_exactly_the_registry_groups_across_two_merges
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)
    @installer.merge_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))

    plastic_groups = settings["hooks"]["PreToolUse"].select do |g|
      g["hooks"].any? { |h| h["command"].to_s.include?("plastic-") }
    end
    assert_equal HookRegistry.events["PreToolUse"].size, plastic_groups.size,
                 "PreToolUse must carry exactly the registry's groups"
  end

  # Intent 226: the retrieval gate is deleted, so nothing may register it.
  def test_pretooluse_registers_no_retrieval_gate
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))

    commands = pretooluse_commands(settings)
    refute commands.any? { |c| c.include?("retrieval-gate") },
      "retrieval-gate must not be registered"
    refute settings["hooks"]["PreToolUse"].any? { |g| g["matcher"] == "Bash|Read|Grep|Glob" },
      "the Bash|Read|Grep|Glob matcher group must be gone"
  end

  def test_pretooluse_create_gate_is_idempotent_across_two_merges
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)
    @installer.merge_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))

    create_commands = pretooluse_commands(settings).select { |c| c.include?("plastic-create-gate") }
    code_commands = pretooluse_commands(settings).select { |c| c.include?("plastic-code-gate") }
    assert_equal 1, create_commands.size, "create-gate must not duplicate across merges"
    assert_equal 1, code_commands.size, "code-gate must not duplicate across merges"
  end

  # Intent 96: the fail-closed lock-gate is registered as a 2nd ordered command
  # INSIDE the write-matcher code-gate group (NOT a new same-matcher group,
  # which the merge loop would collapse). code-gate survives.
  def test_pretooluse_registers_lock_gate_inside_code_gate_group
    settings = merged_settings

    commands = pretooluse_commands(settings)
    assert commands.any? { |c| c.include?("plastic-lock-gate") }, "lock-gate must be registered"
    assert commands.any? { |c| c.include?("plastic-code-gate") }, "code-gate must survive"

    wen_groups = settings["hooks"]["PreToolUse"].select { |g| g["matcher"] == HookRegistry::WRITE_MATCHER }
    assert_equal 1, wen_groups.size, "exactly ONE write-matcher group (no matcher collision)"
    group_commands = wen_groups.first["hooks"].map { |h| h["command"] }
    assert group_commands.any? { |c| c.include?("plastic-code-gate") }, "code-gate in the write group"
    assert group_commands.any? { |c| c.include?("plastic-lock-gate") }, "lock-gate in the write group"
  end

  def test_pretooluse_lock_gate_is_idempotent_across_two_merges
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)
    @installer.merge_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))

    lock_commands = pretooluse_commands(settings).select { |c| c.include?("plastic-lock-gate") }
    assert_equal 1, lock_commands.size, "lock-gate must not duplicate across merges"
    wen_groups = settings["hooks"]["PreToolUse"].select { |g| g["matcher"] == HookRegistry::WRITE_MATCHER }
    assert_equal 1, wen_groups.size, "still exactly ONE write-matcher group after re-merge"
  end

  def test_user_prompt_submit_includes_qmd_search
    File.write(@settings_path, "{}")
    @installer.merge_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))
    group = settings["hooks"]["UserPromptSubmit"].first
    commands = group["hooks"].map { |h| h["command"] }
    assert commands.any? { |c| c.include?("plastic-qmd-search") },
           "UserPromptSubmit must register plastic-qmd-search: #{commands.inspect}"
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
end
