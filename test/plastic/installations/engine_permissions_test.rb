# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/engine_permissions"

class EnginePermissionsTest < Plastic::TestCase
  OWN = "Edit(~/notes/**)"

  def deny(settings)
    settings.dig("permissions", "deny")
  end

  def test_merge_appends_the_entries_after_the_owners_own_rules
    assert_equal [OWN, *Plastic::Installations::EnginePermissions::ENTRIES], deny(Plastic::Installations::EnginePermissions.merge_into({ "permissions" => { "deny" => [OWN] } }))
  end

  def test_merge_twice_adds_each_entry_once
    twice = Plastic::Installations::EnginePermissions.merge_into(Plastic::Installations::EnginePermissions.merge_into({}))

    assert_equal Plastic::Installations::EnginePermissions::ENTRIES, deny(twice)
  end

  def test_merge_replaces_a_deny_value_that_is_not_a_list
    assert_equal Plastic::Installations::EnginePermissions::ENTRIES, deny(Plastic::Installations::EnginePermissions.merge_into({ "permissions" => { "deny" => "all" } }))
  end

  def test_merge_takes_out_the_entry_an_earlier_install_wrote_for_the_scripts_folder
    settings = { "permissions" => { "deny" => [OWN, "Edit(~/.plastic/scripts/**)"] } }

    assert_equal [OWN, *Plastic::Installations::EnginePermissions::ENTRIES], deny(Plastic::Installations::EnginePermissions.merge_into(settings))
  end

  def test_the_retired_entries_name_the_scripts_folder
    assert_equal ["Edit(~/.plastic/scripts/**)"], Plastic::Installations::EnginePermissions::RETIRED
  end

  def test_merge_leaves_the_settings_it_was_given_unchanged
    settings = { "permissions" => { "deny" => [OWN] } }
    Plastic::Installations::EnginePermissions.merge_into(settings)

    assert_equal [OWN], deny(settings)
  end
end
