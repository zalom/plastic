# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/schema_migration"

class SchemaMigrationTest < Plastic::TestCase
  def test_the_line_the_store_of_the_settings_prints_is_printed_by_the_call
    context = call_context(settings: FakeSettings.new(print_once: "config.yml printed from the settings"))

    Plastic::Workflows::SchemaMigration.import_config(context)

    assert_equal ["config.yml printed from the settings"], context.printed
  end

  def test_a_store_with_nothing_to_print_adds_no_line
    context = call_context(settings: FakeSettings.new)

    Plastic::Workflows::SchemaMigration.import_config(context)

    assert_empty context.printed
  end
end
