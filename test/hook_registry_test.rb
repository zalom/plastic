# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/hook_registry"

# HookRegistry.events registers only check-update, the one launcher that still
# ships. This file drives the public methods the installer calls, so a
# missing-events-key crash or a dropped retirement entry fails here instead of
# in a live install.
class HookRegistryTest < Minitest::Test
  def hook_names(hash)
    hash.values.flatten.flat_map { |g| g["hooks"].map { |h| h["name"] } }
  end

  def test_events_registers_only_the_still_shipped_launcher
    assert_equal %w[check-update], hook_names(HookRegistry.events)
  end

  def test_retired_hook_names_carries_every_launcher_that_no_longer_ships
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
