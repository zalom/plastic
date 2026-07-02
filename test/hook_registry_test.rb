require "minitest/autorun"
require "json"
require_relative "../scripts/lib/hook_registry"

# The single source of truth for hook registration (intent 108, D7).
class HookRegistryTest < Minitest::Test
  def test_bash_gate_and_savepoint_pre_are_registered
    pre = HookRegistry.events["PreToolUse"]
    names = pre.flat_map { |g| g["hooks"].map { |h| h["name"] } }
    assert_includes names, "bash-gate"
    assert_includes names, "savepoint-pre"
  end

  def test_write_matcher_covers_mcp_edit_tools
    assert_includes HookRegistry::WRITE_MATCHER, "mcp__serena__replace_content"
    assert_includes HookRegistry::WRITE_MATCHER, "mcp__serena__replace_symbol_body"
    assert_includes HookRegistry::WRITE_MATCHER, "NotebookEdit"
  end

  def test_create_matcher_covers_edit
    assert_includes HookRegistry::CREATE_MATCHER, "Edit"
    assert_includes HookRegistry::CREATE_MATCHER, "Write"
  end

  def test_claude_settings_hooks_builds_plastic_commands
    settings = HookRegistry.claude_settings_hooks(hook_dir: "/x/hooks")
    lock = settings["PreToolUse"].find { |g| g["hooks"].any? { |h| h["command"].include?("lock-gate") } }
    assert_equal "/x/hooks/plastic-lock-gate", lock["hooks"][1]["command"]
  end

  def test_every_registry_hook_name_has_a_launcher_file
    hooks_dir = File.expand_path("../hooks", __dir__)
    HookRegistry.events.each_value do |groups|
      groups.each do |g|
        g["hooks"].each do |h|
          assert File.exist?(File.join(hooks_dir, h["name"])),
                 "hooks/#{h['name']} launcher missing for registered hook"
        end
      end
    end
  end

  # hooks.json (the legacy plugin surface) is pinned to the registry so the two
  # surfaces can never drift again (the divergence that shipped bash-gate dead).
  def test_hooks_json_matches_the_registry
    raw = JSON.parse(File.read(File.expand_path("../hooks/hooks.json", __dir__)))
    json_pre = raw["hooks"]["PreToolUse"].map do |g|
      [g["matcher"], g["hooks"].map { |h| hook_name(h["command"]) }]
    end
    reg_pre = HookRegistry.events["PreToolUse"].map do |g|
      [g["matcher"], g["hooks"].map { |h| h["name"] }]
    end
    assert_equal reg_pre, json_pre
  end

  private

  # `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook" code-gate` -> "code-gate";
  # `"${CLAUDE_PLUGIN_ROOT}/hooks/future-intent-check"` -> "future-intent-check".
  def hook_name(command)
    command[/run-hook" ([a-z-]+)/, 1] || command[/hooks\/([a-z-]+)/, 1]
  end
end
