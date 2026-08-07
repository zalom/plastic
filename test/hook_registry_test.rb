require "minitest/autorun"
require "json"
require_relative "../scripts/lib/hook_registry"

# The single source of truth for hook registration (intent 108, D7).
class HookRegistryTest < Minitest::Test
  def test_bash_gate_and_savepoint_pre_are_registered
    pre = HookRegistry.events["PreToolUse"]
    names = pre.flat_map { |g| g["hooks"].map { |h| h["name"] } }
    assert_includes names, "bash-gate"
    assert_includes HookRegistry::GATE_TOOLS.keys, "savepoint-pre"
  end

  def test_write_matcher_covers_mcp_edit_tools
    assert_includes HookRegistry::WRITE_MATCHER, "mcp__serena__replace_content"
    assert_includes HookRegistry::WRITE_MATCHER, "mcp__serena__replace_symbol_body"
    assert_includes HookRegistry::WRITE_MATCHER, "NotebookEdit"
  end

  def test_claude_settings_hooks_builds_plastic_commands
    settings = HookRegistry.claude_settings_hooks(hook_dir: "/x/hooks")
    lock = settings["PreToolUse"].find { |g| g["hooks"].any? { |h| h["command"].include?("edit-gates") } }
    assert_equal "/x/hooks/plastic-edit-gates", lock["hooks"][0]["command"]
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

  # ACTION_1 (intent 192), repointed at ACTION_6 (intent 244): links-gate's
  # registration collapsed into the single edit-gates dispatcher, so its per-gate
  # applicability now lives in GATE_TOOLS instead of a matcher group.
  def test_links_gate_applies_to_write_and_edit_only
    assert_equal %w[Write Edit], HookRegistry::GATE_TOOLS["links-gate"]
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

    HookRegistry::CODEX_PRE_HOOKS.each do |name|
      expected_status = HookRegistry::GATE_STATUS[name]
      hook = codex["PreToolUse"].first["hooks"].find { |h| h["command"].include?(name) }
      assert_equal expected_status, hook["statusMessage"], "#{name} statusMessage must match GATE_STATUS"
    end
  end

  # Pinning: every Codex hook name must exist either in the single `events`
  # source or in GATE_TOOLS (the edit-path gates that left `events` when
  # Claude's registration collapsed to one hook, intent 244), so a rename in
  # either place cannot silently drift the Codex registration.
  def test_every_codex_hook_name_exists_in_the_events_source
    all_names = HookRegistry.events.values.flatten.flat_map { |g| g["hooks"] }.map { |h| h["name"] } +
                HookRegistry::GATE_TOOLS.keys
    (HookRegistry::CODEX_PRE_HOOKS + HookRegistry::CODEX_POST_HOOKS + HookRegistry::CODEX_BASH_HOOKS).each do |name|
      assert_includes all_names, name, "Codex hook '#{name}' is not registered in HookRegistry.events or GATE_TOOLS"
    end
  end

  # Intent 244, retargeted by post-review fix 6: registration collapsed to
  # ONE PreToolUse hook on the union matcher, so the three matcher groups
  # that used to encode per-gate coverage are gone from `events`. The
  # original version of this test derived its expectations from
  # `%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS`, the SAME building
  # blocks GATE_TOOLS itself is built from, so a change to SERENA_EDIT_TOOLS
  # would move both sides of the assertion together and the pin could never
  # actually fail. These three strings are instead the LITERAL matcher
  # values `hooks/hooks.json` carried at 80dddea, the last commit before this
  # intent's dispatcher collapse landed (captured via
  # `git show 80dddea:hooks/hooks.json`). They are FROZEN pre-change values,
  # the historical truth of what the five gates actually covered, and must
  # NOT be regenerated from current constants (SERENA_EDIT_TOOLS or
  # otherwise): that would silently restore the self-referential pin this
  # fix exists to remove.
  HISTORICAL_FULL_UNION_MATCHER =
    "Write|Edit|NotebookEdit|mcp__serena__replace_content|mcp__serena__replace_symbol_body|" \
    "mcp__serena__insert_after_symbol|mcp__serena__insert_before_symbol|" \
    "mcp__serena__safe_delete_symbol|mcp__serena__rename_symbol".freeze
  HISTORICAL_WRITE_EDIT_MATCHER = "Write|Edit".freeze
  HISTORICAL_CREATE_MATCHER =
    "Write|Edit|mcp__serena__replace_content|mcp__serena__replace_symbol_body|" \
    "mcp__serena__insert_after_symbol|mcp__serena__insert_before_symbol|" \
    "mcp__serena__safe_delete_symbol|mcp__serena__rename_symbol".freeze

  def test_gate_tools_table_derives_todays_three_matcher_groups
    full_union   = HISTORICAL_FULL_UNION_MATCHER.split("|")
    write_edit   = HISTORICAL_WRITE_EDIT_MATCHER.split("|")
    create_tools = HISTORICAL_CREATE_MATCHER.split("|")
    assert_equal full_union.sort,   HookRegistry::GATE_TOOLS["code-gate"].sort
    assert_equal full_union.sort,   HookRegistry::GATE_TOOLS["lock-gate"].sort
    assert_equal write_edit.sort,   HookRegistry::GATE_TOOLS["savepoint-pre"].sort
    assert_equal write_edit.sort,   HookRegistry::GATE_TOOLS["links-gate"].sort
    assert_equal create_tools.sort, HookRegistry::GATE_TOOLS["create-gate"].sort
  end

  def test_the_union_matcher_covers_every_gate_tools_entry
    registered = HookRegistry::WRITE_MATCHER.split("|")
    HookRegistry::GATE_TOOLS.each do |gate, tools|
      (tools - registered).each do |tool|
        flunk "#{gate} lists #{tool}, which the registered matcher never matches"
      end
    end
  end

  # Intent 244: the five gate names left `events` when Claude's registration
  # collapsed, so Codex's statusMessage values now come from GATE_STATUS. Doctor
  # compares command strings only, so nothing else would catch these going empty.
  def test_codex_hooks_json_keeps_every_gate_status_message
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook")
    hooks = codex["PreToolUse"].first["hooks"]
    HookRegistry::CODEX_PRE_HOOKS.each do |name|
      entry = hooks.find { |h| h["command"].include?(name) }
      refute_nil entry, "#{name} must still be registered for Codex"
      refute_empty entry["statusMessage"].to_s, "#{name} lost its statusMessage"
      assert_equal HookRegistry::GATE_STATUS[name], entry["statusMessage"]
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
  # silently, forever. Nothing else in the suite catches that, because a missing
  # launcher fails open to empty output, which the codex hook tests accept.
  def test_codex_dispatcher_relays_every_live_state_hook_name
    src = File.read(File.expand_path("../scripts/codex-hook", __dir__))
    literal = src[/^STATE_HOOKS\s*=\s*%w\[([^\]]*)\]/, 1]
    refute_nil literal, "STATE_HOOKS literal not found in scripts/codex-hook"
    relayed = literal.split
    HookRegistry::CODEX_LIVE_STATE_EVENTS.each do |event|
      names = HookRegistry.events[event].flat_map { |g| g["hooks"].map { |h| h["name"] } }
      names.each do |name|
        assert_includes relayed, name,
          "scripts/codex-hook STATE_HOOKS must relay '#{name}', registered under #{event}"
      end
    end
  end

  private

  # `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook" code-gate` -> "code-gate";
  # `"${CLAUDE_PLUGIN_ROOT}/hooks/future-intent-check"` -> "future-intent-check".
  def hook_name(command)
    command[/run-hook" ([a-z-]+)/, 1] || command[/hooks\/([a-z-]+)/, 1]
  end
end
