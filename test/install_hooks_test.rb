require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"

require_relative "../scripts/lib/installer_core"

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
end
