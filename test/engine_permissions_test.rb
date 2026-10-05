# frozen_string_literal: true

require_relative "test_helper"
require "engine_permissions"

class EnginePermissionsTest < Plastic::TestCase
  OWN = "Edit(~/notes/**)"

  def deny(settings)
    settings.dig("permissions", "deny")
  end

  def test_merge_appends_the_entries_after_the_owners_own_rules
    assert_equal [OWN, *EnginePermissions::ENTRIES], deny(EnginePermissions.merge_into({ "permissions" => { "deny" => [OWN] } }))
  end

  def test_merge_twice_adds_each_entry_once
    twice = EnginePermissions.merge_into(EnginePermissions.merge_into({}))

    assert_equal EnginePermissions::ENTRIES, deny(twice)
  end

  def test_merge_replaces_a_deny_value_that_is_not_a_list
    assert_equal EnginePermissions::ENTRIES, deny(EnginePermissions.merge_into({ "permissions" => { "deny" => "all" } }))
  end

  def test_merge_leaves_the_settings_it_was_given_unchanged
    settings = { "permissions" => { "deny" => [OWN] } }
    EnginePermissions.merge_into(settings)

    assert_equal [OWN], deny(settings)
  end

  def test_remove_keeps_the_owners_rules
    merged = EnginePermissions.merge_into({ "permissions" => { "deny" => [OWN] } })

    assert_equal [OWN], deny(EnginePermissions.remove_from(merged))
  end

  def test_remove_prunes_an_empty_permissions_block
    assert_equal({ "model" => "opus" }, EnginePermissions.remove_from(EnginePermissions.merge_into({ "model" => "opus" })))
  end

  def test_remove_keeps_a_permissions_block_with_other_keys
    merged = EnginePermissions.merge_into({ "permissions" => { "allow" => [OWN] } })

    assert_equal({ "allow" => [OWN] }, EnginePermissions.remove_from(merged)["permissions"])
  end

  def test_remove_leaves_a_deny_value_that_is_not_a_list_alone
    settings = { "permissions" => { "deny" => "all" } }

    assert_same settings, EnginePermissions.remove_from(settings)
  end
end
