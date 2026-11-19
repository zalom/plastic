# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/migration/down"

class MigrationDownTest < Plastic::TestCase
  include PreviousStore

  # The down runs an hour after the migration, so its backup folder sorts last.
  CLOCK = FixedClock::Clock.new(MIGRATED_AT + 3600)

  def down(home, *argv) = plastic("migration", "down", *argv, env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE, clock: CLOCK)

  def revisions(home) = alpha_rows(home, "knowledge_graph.db", "SELECT * FROM document_revisions")

  def kept_file(home) = alpha_rows(home, "knowledge_graph.db", "SELECT name, CAST(data AS TEXT) FROM sqlar")

  def assert_refused_unchanged(home, mention)
    before = [store_bytes(home), backup_folders(home)]
    result = down(home, "--store", "alpha")

    assert_equal [3, ""], [result.code, result.out]
    assert_includes result.err, mention
    assert_equal before, [store_bytes(home), backup_folders(home)]
  end

  def test_a_down_puts_back_document_revisions_and_the_removed_kept_file_in_their_old_shape
    home = migrated_previous_home
    down(home, "--store", "alpha")

    assert_equal [[["sha", "1", "intent.md", "old text", "then", "origin"]], [[ROADMAP, "old roadmap"]]], [revisions(home), kept_file(home)]
  end

  def test_a_down_removes_the_version_from_the_store_and_the_rows_from_legacy_db
    home = migrated_previous_home
    down(home, "--store", "alpha")

    assert_equal [false, []], [recorded(home).include?(DROP), legacy_tables(home)]
  end

  def test_a_down_prints_what_it_put_back_and_offers_the_list_of_the_store_never_plastic_rollback
    result = down(migrated_previous_home, "--store", "alpha")

    assert_call result, code: 0,
      out: ["down: put back 1 row of document_revisions and 1 row of sqlar from legacy.db", "down: alpha no longer records migration #{DROP}", "down: built 0 rows of document_revisions from the current documents", "next: plastic migration list --store alpha"]
    refute_includes result.out, "rollback"
  end

  def test_a_down_takes_a_backup_of_the_store_first
    home = migrated_previous_home
    down(home, "--store", "alpha")
    folder = backup_folders(home).last

    assert_equal "migration down", Plastic::Graph::Backup::Folders.new(alpha_file(home, "")).report(folder).fetch("reason")
  end

  def test_a_down_adds_a_down_row_to_the_ledger
    home = migrated_previous_home
    down(home, "--store", "alpha")

    assert_equal ["alpha", DROP, "down", '{"document_revisions":1,"sqlar":1}', 0], ledger_rows(home).last
  end

  def test_a_store_behind_the_newest_version_is_refused_and_nothing_changes
    assert_refused_unchanged previous_home, "run plastic update"
  end

  def test_a_store_whose_legacy_rows_were_purged_is_refused_and_nothing_changes
    home = migrated_previous_home
    File.delete(alpha_file(home, "legacy.db"))

    assert_refused_unchanged home, "the legacy rows of migration #{DROP} are not in legacy.db"
  end

  def test_a_kept_file_written_again_with_other_bytes_after_the_migration_is_refused_and_nothing_changes
    home = migrated_previous_home
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
      database.execute("INSERT INTO sqlar (name, mode, mtime, sz, data, origin_id) VALUES (?, 420, 0, 0, CAST('new roadmap' AS BLOB), 'o')", [ROADMAP])
    end

    assert_refused_unchanged home, "a row of sqlar changed after migration #{DROP} kept it"
  end

  def test_a_store_newer_than_this_release_is_refused_and_nothing_changes
    home = migrated_previous_home
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("INSERT INTO schema_migrations VALUES ('29991231000000')") }

    assert_refused_unchanged home, "29991231000000"
  end

  def test_a_ledger_that_refuses_the_down_row_leaves_the_store_down_exits_0_and_says_so_on_one_line
    home = migrated_previous_home
    refuse_ledger(home, "down")
    result = down(home, "--store", "alpha")

    assert_equal [0, false, ["down: alpha no longer records migration #{DROP}, but the ledger in plastic.db has no down row for it (refused)"]],
      [result.code, recorded(home).include?(DROP), result.err.lines.map(&:chomp)]
  end

  def test_a_backup_that_fails_stops_the_down_with_exit_1_and_nothing_changes
    home = migrated_previous_home
    FileUtils.mkdir_p(alpha_file(home, "backups"))
    File.chmod(0o555, alpha_file(home, "backups"))
    before = store_bytes(home)
    result = down(home, "--store", "alpha")

    assert_equal [1, before], [result.code, store_bytes(home)]
  ensure
    File.chmod(0o755, alpha_file(home, "backups"))
  end

  def test_a_call_without_store_is_a_usage_error
    result = down(migrated_previous_home)

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "--store"
  end

  def test_a_call_with_project_is_a_usage_error
    result = down(migrated_previous_home, "--store", "alpha", "--project", "alpha")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "--project does not apply"
  end
end
