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

  # ACTION_1 (intent 192): the links-gate hook is registered under the same
  # "Write|Edit" matcher savepoint-pre already uses.
  def test_links_gate_registered_under_write_edit_matcher
    pre = HookRegistry.events["PreToolUse"]
    group = pre.find { |g| g["matcher"] == "Write|Edit" }
    names = group["hooks"].map { |h| h["name"] }
    assert_includes names, "links-gate"
  end

  # --- Codex registration (intent 102) ---

  def test_codex_hooks_json_emits_the_five_gate_savepoint_commands_under_apply_patch
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")

    pre_group = codex["PreToolUse"].first
    assert_equal "apply_patch", pre_group["matcher"]
    names = pre_group["hooks"].map { |h| h["command"][/codex-hook" (\S+)/, 1] }
    assert_equal %w[code-gate lock-gate savepoint-pre links-gate create-gate], names
    pre_group["hooks"].each do |h|
      assert_equal "command", h["type"]
      refute_nil h["statusMessage"]
    end
  end

  def test_codex_hooks_json_emits_post_tool_use_gate_check_under_apply_patch
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")

    post_group = codex["PostToolUse"].first
    assert_equal "apply_patch", post_group["matcher"]
    names = post_group["hooks"].map { |h| h["command"][/codex-hook" (\S+)/, 1] }
    assert_equal %w[gate-check], names
  end

  def test_codex_hooks_json_emits_bash_gate_under_bash_matcher
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")

    bash_group = codex["PreToolUse"].find { |g| g["matcher"] == "Bash" }
    refute_nil bash_group, "a Bash matcher group must be registered for Codex"
    names = bash_group["hooks"].map { |h| h["command"][/codex-hook" (\S+)/, 1] }
    assert_equal %w[bash-gate], names,
      "the Codex Bash matcher carries exactly CODEX_BASH_HOOKS"
    bash_group["hooks"].each do |h|
      assert_equal "command", h["type"]
      refute_nil h["statusMessage"]
    end
  end

  def test_codex_hooks_json_status_message_matches_events_status
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")
    code_gate_status = HookRegistry.events["PreToolUse"]
      .flat_map { |g| g["hooks"] }
      .find { |h| h["name"] == "code-gate" }["status"]

    code_gate_hook = codex["PreToolUse"].first["hooks"].find { |h| h["command"].include?("code-gate") }
    assert_equal code_gate_status, code_gate_hook["statusMessage"]
  end

  # Pinning: every Codex hook name must exist in the single `events` source, so a
  # rename in `events` cannot silently drift the Codex registration.
  def test_every_codex_hook_name_exists_in_the_events_source
    all_names = HookRegistry.events.values.flatten.flat_map { |g| g["hooks"] }.map { |h| h["name"] }
    (HookRegistry::CODEX_PRE_HOOKS + HookRegistry::CODEX_POST_HOOKS + HookRegistry::CODEX_BASH_HOOKS).each do |name|
      assert_includes all_names, name, "Codex hook '#{name}' is not registered in HookRegistry.events"
    end
  end

  # --- Live-state events (intent 199) ---

  def test_codex_hooks_json_emits_session_start_group_projected_from_events
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")
    group = codex["SessionStart"]&.first
    refute_nil group, "SessionStart must be registered for Codex"
    assert_equal "", group["matcher"]
    names = group["hooks"].map { |h| h["command"][/codex-hook" (\S+)/, 1] }
    expected = HookRegistry.events["SessionStart"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    assert_equal expected, names
  end

  def test_codex_hooks_json_emits_user_prompt_submit_group_projected_from_events
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")
    group = codex["UserPromptSubmit"]&.first
    refute_nil group, "UserPromptSubmit must be registered for Codex"
    assert_equal "", group["matcher"]
    names = group["hooks"].map { |h| h["command"][/codex-hook" (\S+)/, 1] }
    expected = HookRegistry.events["UserPromptSubmit"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    assert_equal expected, names
  end

  def test_codex_hooks_json_emits_pre_compact_group_projected_from_events
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")
    group = codex["PreCompact"]&.first
    refute_nil group, "PreCompact must be registered for Codex"
    assert_equal "", group["matcher"]
    names = group["hooks"].map { |h| h["command"][/codex-hook" (\S+)/, 1] }
    expected = HookRegistry.events["PreCompact"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    assert_equal expected, names
  end

  private

  # `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook" code-gate` -> "code-gate";
  # `"${CLAUDE_PLUGIN_ROOT}/hooks/future-intent-check"` -> "future-intent-check".
  def hook_name(command)
    command[/run-hook" ([a-z-]+)/, 1] || command[/hooks\/([a-z-]+)/, 1]
  end
end
