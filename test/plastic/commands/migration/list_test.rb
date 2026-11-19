# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/migration/list"

class MigrationListTest < Plastic::TestCase
  include PreviousStore

  CLOCK = FixedClock::Clock.new(MIGRATED_AT + 3600)

  def list(home) = plastic("migration", "list", "--store", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  def down(home) = plastic("migration", "down", "--store", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  def test_a_list_prints_each_ledger_row_of_the_store
    assert_call list(migrated_to_drop), code: 0,
      out: ["2026-11-19T12:00:00Z  up  #{DROP}  1 row of document_revisions"]
  end

  def test_a_list_names_what_a_down_would_undo_now
    assert_call list(migrated_to_drop), code: 0,
      out: ["down: would undo migration #{DROP} and put back 1 row of document_revisions"]
  end

  def test_a_list_after_a_down_prints_the_down_row_and_no_down_it_would_undo
    home = migrated_to_drop
    down(home)
    result = list(home)

    assert_call result, code: 0, out: ["2026-11-19T13:00:00Z  down  #{DROP}  1 row of document_revisions"]
    refute_includes result.out, "would undo"
  end

  def test_a_list_names_the_newest_version_the_store_records
    assert_call list(migrated_to_drop), code: 0, out: ["store: alpha is at migration #{DROP}"]
  end

  def test_a_list_names_the_rows_legacy_db_holds_for_each_migration
    assert_call list(migrated_to_drop), code: 0, out: ["legacy: migration #{DROP} keeps 1 row of document_revisions"]
  end

  def test_a_list_of_a_store_with_no_legacy_db_says_it_keeps_nothing
    home = migrated_to_drop
    File.delete(alpha_file(home, "legacy.db"))

    assert_call list(home), code: 0, out: ["legacy: alpha keeps no rows in legacy.db"]
  end

  def test_a_list_takes_the_down_from_the_store_when_the_ledger_has_no_row_of_it
    home = migrated_to_drop
    SQLite3::Database.open(File.join(home, "plastic.db")) { |database| database.execute("DELETE FROM store_migrations") }

    assert_call list(home), code: 0,
      out: ["no migration of alpha is in the ledger", "down: would undo migration #{DROP} and put back 1 row of document_revisions"]
  end

  def test_a_list_says_why_a_down_would_be_refused_when_legacy_db_lost_its_rows_and_the_ledger_says_otherwise
    home = migrated_to_drop
    File.delete(alpha_file(home, "legacy.db"))

    assert_call list(home), code: 0,
      out: ["down: the legacy rows of migration #{DROP} are not in legacy.db, so a down cannot undo it; restore a backup to go back"]
  end

  def test_a_list_offers_no_next_command
    refute_includes list(migrated_to_drop).out, "next:"
  end

  def test_a_list_writes_nothing
    home = migrated_to_drop
    before = [store_bytes(home), ledger_rows(home)]
    list(home)

    assert_equal before, [store_bytes(home), ledger_rows(home)]
  end
end
