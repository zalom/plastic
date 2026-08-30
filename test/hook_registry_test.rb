require "minitest/autorun"
require "json"
require_relative "../scripts/lib/hook_registry"

# The single source of truth for hook registration (intent 108, D7). Since intent 302
# there is no PreToolUse event at all: the edit-path gates are gone, and the only
# write-path hook is `record` under PostToolUse.
class HookRegistryTest < Minitest::Test
  def test_no_pre_tool_use_event_is_registered
    refute HookRegistry.events.key?("PreToolUse"), "the edit-path gates were removed in 2.0 (intent 302)"
    %i[GATE_TOOLS CODEX_GATE_TOOLS CODEX_PRE_HOOKS CODEX_BASH_HOOKS].each do |const| # removed in 2.0
      refute HookRegistry.const_defined?(const), "HookRegistry::#{const} must be gone with the gates"
    end
  end

  def test_write_matcher_covers_mcp_edit_tools
    assert_includes HookRegistry::WRITE_MATCHER, "mcp__serena__replace_content"
    assert_includes HookRegistry::WRITE_MATCHER, "mcp__serena__replace_symbol_body"
    assert_includes HookRegistry::WRITE_MATCHER, "NotebookEdit"
  end

  def test_record_is_the_sole_write_matcher_hook_under_post_tool_use
    groups = HookRegistry.events["PostToolUse"]
    assert_equal 1, groups.size
    assert_equal HookRegistry::WRITE_MATCHER, groups.first["matcher"]
    assert_equal %w[record], groups.first["hooks"].map { |h| h["name"] }
  end

  def test_claude_settings_hooks_builds_plastic_commands
    settings = HookRegistry.claude_settings_hooks(hook_dir: "/x/hooks")
    record = settings["PostToolUse"]
    assert_equal "/x/hooks/plastic-record", record["hooks"][0]["command"]
    refute settings.key?("PreToolUse")
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

  def test_session_end_registers_close_for_claude_and_hooks_json_carries_it
    names = HookRegistry.events["SessionEnd"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    assert_equal ["close"], names
    raw = JSON.parse(File.read(File.expand_path("../hooks/hooks.json", __dir__)))
    json_names = raw["hooks"]["SessionEnd"].flat_map { |g| g["hooks"].map { |h| hook_name(h["command"]) } }
    assert_equal ["close"], json_names
    # Intent 309: Codex's SessionEnd projection is its own constant (CODEX_SESSION_END_HOOKS),
    # never a fourth live-state event: the close hook is handed off detached, not relayed.
    refute_includes HookRegistry::CODEX_LIVE_STATE_EVENTS, "SessionEnd"
    assert_equal %w[close], HookRegistry::CODEX_SESSION_END_HOOKS
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")
    group = codex["SessionEnd"].first
    assert_equal "", group["matcher"]
    assert_equal ["close"], group["hooks"].map { |h| h["command"][/codex-hook" (\S+)/, 1] }
    assert_equal "Closing the Plastic session...", group["hooks"].first["statusMessage"]
  end

  # hooks.json (the legacy plugin surface) is pinned to the registry so the two
  # surfaces can never drift again: same events, same hook names per event.
  def test_hooks_json_matches_the_registry
    raw = JSON.parse(File.read(File.expand_path("../hooks/hooks.json", __dir__)))["hooks"]
    assert_equal HookRegistry.events.keys.sort, raw.keys.sort
    HookRegistry.events.each do |event, groups|
      reg = groups.flat_map { |g| g["hooks"].map { |h| h["name"] } }
      json = raw[event].flat_map { |g| g["hooks"].map { |h| hook_name(h["command"]) } }
      assert_equal reg, json, "hooks.json #{event} drifted from the registry"
    end
    refute raw.key?("PreToolUse")
  end

  # --- Codex registration (intent 102) ---

  def test_codex_hooks_json_has_no_pre_tool_use_group
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")
    assert_equal %w[PostToolUse PreCompact SessionEnd SessionStart UserPromptSubmit], codex.keys.sort
  end

  def test_codex_hooks_json_emits_post_tool_use_record_under_apply_patch
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")

    post_group = codex["PostToolUse"].first
    assert_equal "apply_patch", post_group["matcher"]
    names = post_group["hooks"].map { |h| h["command"][/codex-hook" (\S+)/, 1] }
    assert_equal %w[record], names
    assert_equal "command", post_group["hooks"].first["type"]
  end

  def test_codex_hooks_json_status_message_matches_events_status
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")
    events_status = HookRegistry.events.values.flatten.flat_map { |g| g["hooks"] }
                                 .each_with_object({}) { |h, m| m[h["name"]] = h["status"] }
    codex.each_value do |groups|
      groups.flat_map { |g| g["hooks"] }.each do |hook|
        name = hook["command"][/codex-hook" (\S+)/, 1]
        assert_equal events_status[name], hook["statusMessage"],
          "#{name} statusMessage must match the one events carries"
        refute_empty hook["statusMessage"].to_s, "#{name} lost its statusMessage" unless name == "check-update"
      end
    end
  end

  def test_codex_hook_names_are_the_six_live_names
    assert_equal %w[capture check-update close record savepoint session-start],
                 HookRegistry.codex_hook_names
  end

  # Pinning: every Codex hook name must exist in the single `events` source, so a
  # rename there cannot silently drift the Codex registration.
  def test_every_codex_hook_name_exists_in_the_events_source
    all_names = HookRegistry.events.values.flatten.flat_map { |g| g["hooks"] }.map { |h| h["name"] }
    HookRegistry.codex_hook_names.each do |name|
      assert_includes all_names, name, "Codex hook '#{name}' is not registered in HookRegistry.events"
    end
  end

  # Intent 302: every gate name Plastic ever registered is purge-only now, and none
  # of them may read as a current launcher.
  def test_retired_hook_names_carry_every_removed_gate
    %w[edit-gates bash-gate savepoint-pre code-gate lock-gate links-gate create-gate gate-check power-tools].each do |name|
      assert_includes HookRegistry::RETIRED_HOOK_NAMES, name
      refute_includes HookRegistry.claude_launcher_names, "plastic-#{name}"
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

  # Intent 246, D8. scripts/codex-hook's STATE_HOOKS array is a hand-kept
  # literal, unlike claude_launcher_names which derives from `events`. A hook
  # renamed in `events` but not in that array leaves the Codex dispatcher
  # relaying a name it does not recognise: it falls past the STATE_HOOKS branch
  # into the apply_patch path, hits `exit 0 if ops.empty?`, and emits nothing,
  # silently, forever.
  def test_codex_dispatcher_relays_every_live_state_hook_name
    src = File.read(File.expand_path("../scripts/codex-hook", __dir__))
    literal = src[/^STATE_HOOKS\s*=\s*%w\[([^\]]*)\]/, 1]
    refute_nil literal, "STATE_HOOKS literal not found in scripts/codex-hook"
    relayed = literal.split
    HookRegistry::CODEX_SESSION_END_HOOKS.each do |name|
      assert_includes relayed, name, "scripts/codex-hook STATE_HOOKS must relay '#{name}' (SessionEnd, intent 309)"
    end
    HookRegistry::CODEX_LIVE_STATE_EVENTS.each do |event|
      names = HookRegistry.events[event].flat_map { |g| g["hooks"].map { |h| h["name"] } }
      names.each do |name|
        assert_includes relayed, name,
          "scripts/codex-hook STATE_HOOKS must relay '#{name}', registered under #{event}"
      end
    end
  end

  # Intent 250: the reverse direction. Delete or rename a hook in `events` and its
  # old name must not linger in STATE_HOOKS as dead wiring that reads as live.
  def test_codex_dispatcher_names_no_state_hook_the_registry_does_not_register
    src = File.read(File.expand_path("../scripts/codex-hook", __dir__))
    literal = src[/^STATE_HOOKS\s*=\s*%w\[([^\]]*)\]/, 1]
    refute_nil literal, "STATE_HOOKS literal not found in scripts/codex-hook"
    live_events = HookRegistry::CODEX_LIVE_STATE_EVENTS
    registered = live_events.flat_map do |event|
      HookRegistry.events[event].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    end + HookRegistry::CODEX_SESSION_END_HOOKS
    literal.split.each do |name|
      assert_includes registered, name,
        "scripts/codex-hook STATE_HOOKS relays '#{name}', but no hook by that name is " \
        "registered for Codex under #{live_events.join(', ')}."
    end
    refute_match(/^SHELL_HOOKS\s*=/, src, "the shell-tool branch left with bash-gate (intent 302)")
  end

  # Intent 277: the current-only predicate hooks_registered needs. Rows two and
  # three are the ones that separate it from claude_purge_command?, which answers
  # true for both.
  def test_claude_current_predicate_truth_table
    assert HookRegistry.claude_current_command?("/Users/x/.claude/hooks/plastic-session-start")
    assert HookRegistry.claude_current_command?("ruby /Users/x/.claude/hooks/plastic-session-start.rb")
    assert HookRegistry.claude_current_command?("\"/Users/x/my hooks/plastic-savepoint\"")

    refute HookRegistry.claude_current_command?("/Users/x/.claude/hooks/plastic-lock-gate")
    refute HookRegistry.claude_current_command?("/Users/x/.claude/hooks/plastic-edit-gates")
    refute HookRegistry.claude_current_command?("/Users/x/.claude/hooks/plastic-bash-gate")
    refute HookRegistry.claude_current_command?("/Users/x/.claude/hooks/plastic-statusline")
    refute HookRegistry.claude_current_command?("~/.claude/hooks/plastic-writing-style")
    refute HookRegistry.claude_current_command?("serena-hooks activate --client=claude-code")
    refute HookRegistry.claude_current_command?("")
  end

  # Drift pin, the mirror of install_hooks_test.rb's
  # test_every_registered_claude_command_is_purgeable: every command the registry
  # generates must read as current, or a freshly-merged settings.json would fail
  # doctor's hooks_registered the moment the installer finished writing it.
  def test_every_registered_claude_command_is_current
    commands = HookRegistry.claude_settings_hooks(hook_dir: "/tmp/h").values.flatten.flat_map do |g|
      g["hooks"].map { |h| h["command"] }
    end
    refute_empty commands
    commands.each do |cmd|
      assert HookRegistry.claude_current_command?(cmd), "#{cmd} must read as a current registration"
    end
  end

  private

  # `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook" record` -> "record";
  # `"${CLAUDE_PLUGIN_ROOT}/hooks/check-update"` -> "check-update".
  def hook_name(command)
    command[/run-hook" ([a-z-]+)/, 1] || command[/hooks\/([a-z-]+)/, 1]
  end
end
