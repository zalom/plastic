# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/schema_migration"

class SchemaMigrationTest < Plastic::TestCase
  include PreviousStore

  ALL = Plastic::Graph::MIGRATIONS.versions(:store)
  RETIRED = "migrate.drop_document_revisions"
  RETIRED_ROWS = "20261125090000"

  def bring_alpha_current(home)
    harness = scoped_harness(env: { "PLASTIC_HOME" => home }, settings: FakeSettings.new)
    Plastic::Workflows::SchemaMigration.bring_current(call_context(harness:), slug: "alpha")
  end

  # An empty home with the project alpha registered and its store made by this code, as a clean install leaves it.
  def clean_home
    home = File.join(Dir.mktmpdir, ".plastic")
    FileUtils.mkdir_p(File.join(home, "stores", "alpha"))
    File.write(File.join(home, "projects.yml"), "projects:\n  alpha:\n    path: #{Dir.mktmpdir}\n")
    Plastic::Graph.create(home:, store: "alpha")
    forget(home)
    home
  end

  def test_a_store_of_the_previous_release_runs_every_migration_with_no_switch
    home = previous_home

    assert_equal [["alpha"], ALL], [bring_alpha_current(home).migrated, recorded(home)]
  ensure
    forget(home)
  end

  def test_a_clean_home_records_every_migration_and_leaves_none_to_run
    home = clean_home

    assert_equal [[], ALL], [bring_alpha_current(home).migrated, recorded(home)]
  ensure
    forget(home)
  end

  # A home of the previous release: its settings hold the retired switch in the global scope and for one harness,
  # beside a setting that stays, config.yml is printed from them, and plastic.db lacks the home migration that removes
  # the switch.
  def home_with_the_retired_switch
    home = clean_home
    store = Plastic::Wiring.store(home)
    [["global", RETIRED, true], ["global", "screens", false], ["codex", RETIRED, true]].each { |row| store.set(*row) }
    SQLite3::Database.open(File.join(home, "plastic.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [RETIRED_ROWS]) }
    forget(home)
    home
  end

  def bring_home_current(home)
    harness = scoped_harness(env: { "PLASTIC_HOME" => home }, settings: Plastic::Wiring.settings(home))
    Plastic::Workflows::SchemaMigration.bring_current(call_context(harness:))
  end

  def setting_rows(home) = SQLite3::Database.open(File.join(home, "plastic.db"), readonly: true) { |database| database.execute("SELECT scope, key, value FROM settings ORDER BY scope, key") }

  def test_the_update_removes_the_retired_switch_from_the_settings_rows_and_from_config_yml
    home = home_with_the_retired_switch
    bring_home_current(home)

    assert_equal [[["global", "screens", "false"]], { "version" => 3, "global" => { "screens" => false } }],
      [setting_rows(home), YAML.safe_load_file(File.join(home, "config.yml"))]
  ensure
    forget(home)
  end

  def test_the_line_the_store_of_the_settings_prints_is_printed_by_the_call
    context = call_context(harness: scoped_harness(settings: FakeSettings.new(print_current: "config.yml printed from the settings")))

    Plastic::Workflows::SchemaMigration.import_config(context)

    assert_equal ["config.yml printed from the settings"], context.printed
  end

  def test_a_store_with_nothing_to_print_adds_no_line
    context = call_context(harness: scoped_harness(settings: FakeSettings.new))

    Plastic::Workflows::SchemaMigration.import_config(context)

    assert_empty context.printed
  end
end
