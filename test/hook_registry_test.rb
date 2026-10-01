# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/hook_registry"

# Intent 397 cutover: HookRegistry.events now registers only check-update, the one
# launcher Step 3 left on disk (session-start, savepoint, record, close, capture,
# message-display, stop, and the codex-hook dispatcher are gone with their scripts).
# The Codex-side constants are empty until intent 398 gives Codex its own hook
# resume and hook record entries. This file drives the public methods the
# installer calls, so a missing-events-key crash or a dropped retirement entry
# fails here instead of in a live install.
class HookRegistryTest < Minitest::Test
  def hook_names(hash)
    hash.values.flatten.flat_map { |g| g["hooks"].map { |h| h["name"] } }
  end

  def test_events_registers_only_the_still_shipped_launcher
    assert_equal %w[check-update], hook_names(HookRegistry.events)
  end

  def test_codex_hooks_json_has_no_names_to_project_yet
    result = HookRegistry.codex_hooks_json(dispatcher_path: "/tmp/codex-hook")
    all_hooks = result.values.flatten.flat_map { |g| g["hooks"] }
    assert_empty all_hooks
  end

  def test_retired_hook_names_carries_every_launcher_this_cutover_dropped
    %w[session-start savepoint record close capture message-display stop].each do |name|
      assert_includes HookRegistry::RETIRED_HOOK_NAMES, name
    end
  end

  def test_claude_launcher_names_matches_events
    assert_equal %w[plastic-check-update], HookRegistry.claude_launcher_names
  end

  def test_claude_purgeable_launcher_names_still_recognises_a_retired_launcher
    assert_includes HookRegistry.claude_purgeable_launcher_names, "plastic-session-start"
  end

  def test_claude_settings_hooks_shape_for_a_single_group_event
    hooks = HookRegistry.claude_settings_hooks(hook_dir: "/tmp/hooks")
    session_start = hooks["SessionStart"]
    assert_equal "", session_start["matcher"]
    assert_equal "/tmp/hooks/plastic-check-update", session_start["hooks"].first["command"]
  end
end
