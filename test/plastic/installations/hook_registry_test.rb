# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/hook_registry"

# Plastic::Installations::HookRegistry.events registers no launcher. This file drives the public methods the installer calls, so a
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

  REGISTERED = { "SessionStart" => [{ "matcher" => "startup", "hooks" => [{ "name" => "check-update", "status" => "Checking" }] }] }.freeze

  def test_the_launcher_names_come_from_the_registered_events
    assert_equal ["plastic-check-update"], Plastic::Installations::HookRegistry.claude_launcher_names(REGISTERED)
  end

  def test_a_command_running_a_registered_launcher_is_current_and_another_is_not
    registry = Plastic::Installations::HookRegistry

    assert_equal [true, false], [registry.claude_current_command?("/h/plastic-check-update", REGISTERED), registry.claude_current_command?("/h/other", REGISTERED)]
  end

  def test_one_group_for_an_event_maps_to_a_hash_with_the_launcher_command
    hooks = Plastic::Installations::HookRegistry.claude_settings_hooks(hook_dir: "/h", registered: REGISTERED)

    assert_equal({ "SessionStart" => { "matcher" => "startup", "hooks" => [{ "type" => "command", "command" => "/h/plastic-check-update", "statusMessage" => "Checking" }] } }, hooks)
  end

  def test_two_groups_for_an_event_map_to_an_array
    registered = { "Stop" => REGISTERED["SessionStart"] * 2 }

    assert_equal 2, Plastic::Installations::HookRegistry.claude_settings_hooks(hook_dir: "/h", registered:)["Stop"].size
  end

  def test_claude_settings_hooks_are_empty_while_no_launcher_is_registered
    assert_empty Plastic::Installations::HookRegistry.claude_settings_hooks(hook_dir: "/tmp/hooks")
  end
end
