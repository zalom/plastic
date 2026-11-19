# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/migration/purge"

class MigrationPurgeTest < Plastic::TestCase
  include PreviousStore

  BASELINE = "20261117000000"
  CLOCK = FixedClock::Clock.new(MIGRATED_AT + 3600)

  def purge(home, *argv) = plastic("migration", "purge", *argv, env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  def free_pages(home) = alpha_rows(home, "legacy.db", "PRAGMA freelist_count").flatten.first

  def assert_usage_unchanged(home, version, mention)
    before = [store_bytes(home), ledger_rows(home)]
    result = purge(home, version, "--store", "alpha")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, mention
    assert_equal before, [store_bytes(home), ledger_rows(home)]
  end

  def test_a_purge_removes_the_legacy_rows_of_the_migration_and_leaves_its_version_in_the_store
    home = migrated_previous_home
    purge(home, DROP, "--store", "alpha")

    assert_equal [[], true], [legacy_tables(home), recorded(home).include?(DROP)]
  end

  def test_a_purge_gives_the_space_of_the_removed_rows_back_to_the_disk
    home = migrated_previous_home
    purge(home, DROP, "--store", "alpha")

    assert_equal 0, free_pages(home)
  end

  def test_a_purge_prints_what_it_removed_and_that_the_migration_can_no_longer_be_undone
    assert_call purge(migrated_previous_home, DROP, "--store", "alpha"), code: 0,
      out: ["purge: removed 1 row of document_revisions and 1 row of sqlar from legacy.db", "purge: migration #{DROP} of alpha can no longer be undone"]
  end

  def test_a_ledger_that_refuses_the_purge_row_leaves_the_rows_purged_exits_0_and_says_so_on_one_line
    home = migrated_previous_home
    refuse_ledger(home, "purge")
    result = purge(home, DROP, "--store", "alpha")

    assert_equal [0, [], ["purge: the rows migration #{DROP} kept are gone from legacy.db of alpha, but the ledger in plastic.db has no purge row for it (plastic.db: refused)"]],
      [result.code, legacy_tables(home), result.err.lines.map(&:chomp)]
  end

  def test_a_purge_adds_a_purge_row_to_the_ledger
    home = migrated_previous_home
    purge(home, DROP, "--store", "alpha")

    assert_equal ["alpha", DROP, "purge", '{"document_revisions":1,"sqlar":1}', 0], ledger_rows(home).last
  end

  def test_after_a_purge_a_down_is_refused
    home = migrated_previous_home
    purge(home, DROP, "--store", "alpha")
    result = plastic("migration", "down", "--store", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

    assert_equal 3, result.code
  end

  def test_a_version_purged_already_is_a_usage_error_and_nothing_changes
    home = migrated_previous_home
    purge(home, DROP, "--store", "alpha")

    assert_usage_unchanged home, DROP, "migration #{DROP} keeps no rows of alpha in legacy.db"
  end

  def test_a_version_that_kept_nothing_is_a_usage_error_and_nothing_changes
    assert_usage_unchanged migrated_previous_home, BASELINE, "migration #{BASELINE} keeps no rows of alpha in legacy.db"
  end

  def test_a_store_with_no_legacy_db_is_a_usage_error_and_gets_no_legacy_db
    home = previous_home
    result = purge(home, DROP, "--store", "alpha")

    assert_equal [2, false], [result.code, File.exist?(alpha_file(home, "legacy.db"))]
  end

  def test_a_call_without_a_version_is_a_usage_error
    assert_equal 2, purge(migrated_previous_home, "--store", "alpha").code
  end

  def test_a_call_with_project_is_a_usage_error
    result = purge(migrated_previous_home, DROP, "--store", "alpha", "--project", "alpha")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "--project does not apply"
  end
end
