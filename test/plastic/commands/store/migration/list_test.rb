# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/commands/store/migration/list"

class MigrationListTest < Plastic::TestCase
  include PreviousStore

  CLOCK = FixedClock::Clock.new(MIGRATED_AT + 3600)

  def list(home) = plastic("store", "migration", "list", "--project", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  def down(home) = plastic("store", "migration", "down", "--project", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  def json_list(home) = plastic("store", "migration", "list", "--project", "alpha", "--json", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  # A home whose store alpha this release made, so it records every migration and its legacy.db holds nothing.
  def fresh_home
    home = File.join(Dir.mktmpdir, ".plastic")
    FileUtils.mkdir_p(File.join(home, "stores", "alpha"))
    File.write(File.join(home, "projects.yml"), "projects:\n  alpha:\n    path: #{Dir.mktmpdir}\n")
    Plastic::Graph.create(home:, store: "alpha")
    forget(home)
    home
  end

  def fresh_lines(home)
    newest = recorded(home).last
    [
      "store: alpha is at migration #{newest}",
      "legacy: alpha keeps no rows in legacy.db",
      "no migration of alpha is in the ledger",
      "down: would undo migration #{newest} and put back no rows"
    ]
  end

  def test_a_list_of_a_fresh_store_prints_every_line
    home = fresh_home

    assert_call list(home), code: 0, out: /\A#{Regexp.escape(fresh_lines(home).map { |line| "#{line}\n" }.join)}because: /
  end

  def test_a_list_of_a_fresh_store_in_json_gives_every_line
    home = fresh_home
    result = json_list(home)

    assert_call result, code: 0, out: /"output"/
    assert_equal fresh_lines(home), JSON.parse(result.out).dig("result", "output")
  end

  def test_a_list_says_the_newest_migration_that_kept_nothing_puts_back_no_rows
    home = migrated_previous_home_with_times

    assert_call list(home), code: 0,
      out: ["legacy: migration #{UTC} keeps 1 row of changed_values", "down: would undo migration #{recorded(home).last} and put back no rows\n"]
  end

  def test_a_list_prints_each_ledger_row_of_the_store_in_the_zone_of_the_machine
    assert_call list(migrated_to_owner), code: 0,
      out: ["#{shown("2026-11-19T12:00:00Z")}  up  #{UTC}  1 row of changed_values"]
  end

  def test_a_list_names_what_a_down_would_undo_now
    assert_call list(migrated_to_owner), code: 0,
      out: ["down: would undo migration #{UTC} and put back 1 row of changed_values"]
  end

  def test_a_list_after_a_down_prints_the_down_row_and_the_down_it_would_undo_next
    home = migrated_to_owner
    down(home)
    result = list(home)

    assert_call result, code: 0, out: ["#{shown("2026-11-19T13:00:00Z")}  down  #{UTC}  1 row of changed_values"]
    assert_includes result.out, "down: would undo migration 20261120090000 and put back no rows"
  end

  def test_a_list_names_the_newest_version_the_store_records
    assert_call list(migrated_to_owner), code: 0, out: ["store: alpha is at migration #{UTC}"]
  end

  def test_a_list_names_the_rows_legacy_db_holds_for_each_migration
    assert_call list(migrated_to_owner), code: 0, out: ["legacy: migration #{UTC} keeps 1 row of changed_values"]
  end

  def test_a_list_of_a_store_with_no_legacy_db_says_it_keeps_nothing
    home = migrated_to_owner
    File.delete(alpha_file(home, "legacy.db"))

    assert_call list(home), code: 0, out: ["legacy: alpha keeps no rows in legacy.db"]
  end

  def test_a_list_takes_the_down_from_the_store_when_the_ledger_has_no_row_of_it
    home = migrated_to_owner
    SQLite3::Database.open(File.join(home, "plastic.db")) { |database| database.execute("DELETE FROM store_migrations") }

    assert_call list(home), code: 0,
      out: ["no migration of alpha is in the ledger", "down: would undo migration #{UTC} and put back 1 row of changed_values"]
  end

  def test_a_list_offers_no_next_command
    refute_includes list(migrated_to_owner).out, "next:"
  end

  def test_a_list_writes_nothing
    home = migrated_to_owner
    before = [store_bytes(home), ledger_rows(home)]
    list(home)

    assert_equal before, [store_bytes(home), ledger_rows(home)]
  end
end
