# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/hook_registry"

# Plastic::Installations::HookRegistry.events registers only check-update, the one launcher that still
# ships. This file drives the public methods the installer calls, so a
# missing-events-key crash or a dropped retirement entry fails here instead of
# in a live install.
class HookRegistryTest < Minitest::Test
  def hook_names(hash)
    hash.values.flatten.flat_map { |g| g["hooks"].map { |h| h["name"] } }
  end

  def test_events_registers_no_launcher
    assert_empty hook_names(Plastic::Installations::HookRegistry.events)
  end

  def test_retired_hook_names_carries_every_launcher_that_no_longer_ships
    %w[session-start savepoint record close capture message-display stop].each do |name|
      assert_includes Plastic::Installations::HookRegistry::RETIRED_HOOK_NAMES, name
    end
  end

  def test_claude_launcher_names_matches_events
    assert_empty Plastic::Installations::HookRegistry.claude_launcher_names
  end

  def test_claude_purgeable_launcher_names_still_recognises_a_retired_launcher
    assert_includes Plastic::Installations::HookRegistry.claude_purgeable_launcher_names, "plastic-session-start"
  end

  def test_claude_settings_hooks_are_empty_while_no_launcher_is_registered
    assert_empty Plastic::Installations::HookRegistry.claude_settings_hooks(hook_dir: "/tmp/hooks")
  end
end
