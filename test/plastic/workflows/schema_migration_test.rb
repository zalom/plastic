# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/schema_migration"

class SchemaMigrationTest < Plastic::TestCase
  include PreviousStore

  SWITCH = "migrate.drop_document_revisions"

  def bring_alpha_current(home, values)
    harness = scoped_harness(env: { "PLASTIC_HOME" => home }, settings: Plastic::Workflows::FakeSettings.new(values:))
    Plastic::Workflows::SchemaMigration.bring_current(call_context(harness:), slug: "alpha")
  end

  def test_a_store_runs_a_held_migration_once_the_settings_turn_its_switch_on
    home = previous_home

    assert_equal [["alpha"], true], [bring_alpha_current(home, { SWITCH => true }).migrated, recorded(home).include?(DROP)]
  ensure
    forget(home)
  end

  def test_a_store_skips_a_held_migration_while_the_settings_leave_its_switch_off
    home = previous_home

    assert_equal [[], false], [bring_alpha_current(home, {}).migrated, recorded(home).include?(DROP)]
  ensure
    forget(home)
  end

  def test_the_line_the_store_of_the_settings_prints_is_printed_by_the_call
    context = call_context(harness: scoped_harness(settings: FakeSettings.new(print_once: "config.yml printed from the settings")))

    Plastic::Workflows::SchemaMigration.import_config(context)

    assert_equal ["config.yml printed from the settings"], context.printed
  end

  def test_a_store_with_nothing_to_print_adds_no_line
    context = call_context(harness: scoped_harness(settings: FakeSettings.new))

    Plastic::Workflows::SchemaMigration.import_config(context)

    assert_empty context.printed
  end
end
