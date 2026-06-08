require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"

INSTALL_RB = File.expand_path("../../scripts/install.rb", __FILE__)

code = File.read(INSTALL_RB)
code = code.sub(/^main$/, "# main (suppressed by test)")
code = code.sub(/^PACKAGE_ROOT = .*$/, 'PACKAGE_ROOT = "/tmp/plastic-test-pkg"')
code = code.sub(/^VERSION = .*$/, 'VERSION = "1.0.0-test"')
eval(code, TOPLEVEL_BINDING, INSTALL_RB)

class MergeClaudeHooksTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("hooks-test")
    @settings_path = File.join(@dir, "settings.json")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_merge_into_empty_settings
    File.write(@settings_path, "{}")
    merge_claude_hooks(@settings_path)

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
    merge_claude_hooks(@settings_path)

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
    merge_claude_hooks(@settings_path)

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
    merge_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    plastic_group = settings["hooks"]["SessionStart"].find { |g| g["hooks"].any? { |h| h["command"].include?("plastic-") } }

    assert plastic_group, "Plastic group should exist"
    assert_equal 2, plastic_group["hooks"].size, "Should have session-start + check-update"
    assert plastic_group["hooks"].none? { |h| h["command"].include?("/old/path/") }, "Old path should be replaced"
  end

  def test_remove_claude_hooks
    File.write(@settings_path, "{}")
    merge_claude_hooks(@settings_path)

    remove_claude_hooks(@settings_path)
    settings = JSON.parse(File.read(@settings_path))

    assert_nil settings["hooks"], "All plastic hooks should be removed"
    assert_nil settings["statusLine"], "statusLine should be removed"
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
    remove_claude_hooks(@settings_path)

    settings = JSON.parse(File.read(@settings_path))
    assert_equal 1, settings["hooks"]["SessionStart"].size, "Only serena group should remain"
    assert_nil settings["statusLine"], "Plastic statusLine should be removed"
  end
end
