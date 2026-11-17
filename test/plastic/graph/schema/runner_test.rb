# frozen_string_literal: true

require "digest"
require_relative "../../../test_helper"

class SchemaRunnerTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Runner = Plastic::Graph::SchemaRunner
  Sequences = Plastic::Graph::SchemaSequences
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def run_runner(home, **options) = Runner.new(home:, now: NOW, **options).call

  def old_home = old_layout(fresh_home)

  def store_files(home, slug = "alpha") = Dir.glob(File.join(home, "stores", slug, "*.db")).sort

  def test_an_old_layout_home_migrated_through_every_migration_has_the_layout_of_a_new_database
    home = old_home
    run_runner(home)

    assert_equal layouts(fresh_home), layouts(home)
  end

  def test_the_home_and_the_knowledge_database_are_stamped_and_the_other_store_databases_stay_unstamped
    home = old_home
    run_runner(home)
    versions = user_versions(home).transform_keys { |path| path.delete_prefix(home) }

    stamped = versions.group_by { |path, _| File.basename(path) }.transform_values { |pairs| pairs.map(&:last).uniq }

    assert_equal({ "plastic.db" => [Sequences.newest(:home)], "knowledge_graph.db" => [Plastic::Graph::SchemaMigrator::VERSION], "work_graph.db" => [0], "retrieval_graph.db" => [0] }, stamped)
  end

  def test_a_backup_of_the_store_is_taken_first_and_says_it_is_the_migration_backup
    home = old_home
    run_runner(home)
    report = Plastic::Graph::Backup::Folders.new(File.join(home, "stores", "alpha")).report(folder_names(home).first)

    assert_equal ["migration", 0, "done"], report.values_at("reason", "version", "status")
  end

  def test_a_fresh_backup_does_not_stop_the_runner_from_taking_its_own
    home = old_home
    Plastic::Graph::Backup::Writer.new(File.join(home, "stores", "alpha"), "alpha", now: NOW - 60).call
    run_runner(home)

    assert_equal 2, folder_names(home).size
  end

  def test_a_home_that_is_current_changes_no_byte_and_takes_no_backup
    home = old_home
    run_runner(home)
    before = file_bytes(home)
    count = folder_names(home).size
    run_runner(home)

    assert_equal [before, count], [file_bytes(home), folder_names(home).size]
  end

  def test_a_store_whose_backup_fails_stays_behind_and_the_other_store_migrates
    home = old_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.write(store_file(home, "work_graph"), "not a database")
    before = bytes_in(home, "/alpha/")
    report = run_runner(home)

    assert_equal [["alpha"], before], [report.failed.keys, bytes_in(home, "/alpha/")]
    assert_equal Plastic::Graph::SchemaMigrator::VERSION, user_versions(home).fetch(store_file(home, "knowledge_graph", "beta"))
  end

  def test_a_store_whose_backup_folder_cannot_be_written_stays_behind
    home = old_home
    FileUtils.mkdir_p(File.join(home, "stores", "alpha", "backups"), mode: 0o555)
    bytes_in(home, "/alpha/")
    report = run_runner(home)

    assert_equal [["alpha"], [0]], [report.failed.keys, versions_in(home, "/alpha/")]
  end

  def test_backup_migrate_restore_and_migrate_again_give_equal_row_digests
    home = old_home
    run_runner(home)
    migrated = store_digests(home).except("retrieval_graph.db")
    Plastic::Graph::Database::ConnectionPool.release(home)
    restore_call(home, "--store", "alpha", "--latest")

    assert_equal [Plastic::Graph::SchemaMigrator::VERSION], versions_in(home, "/alpha/knowledge_graph.db")
    assert_equal migrated, store_digests(home).except("retrieval_graph.db")
  end

  def bytes_in(home, part) = file_bytes(home).select { |path, _| path.include?(part) }

  def versions_in(home, part) = user_versions(home).select { |path, _| path.include?(part) }.values.uniq

  def store_digests(home) = store_files(home).to_h { |path| [File.basename(path), row_digest(path)] }
end
